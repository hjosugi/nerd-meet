defmodule NerdMeet.Accounts do
  @moduledoc """
  Identity: who an account belongs to, and whether this sign-in is really them.

  Two rules shape everything here.

  **Verification happens outside transactions.** `register/1` talks to the
  identity provider first and only then opens a `Multi`. A database connection
  held open across a network call to someone else's endpoint turns their
  latency into our outage.

  **A cloned authenticator is not a risk score.** Every other signal adds
  points and may ask for a second factor. A signature counter that fails to
  advance revokes every credential on the account immediately, because the
  device that was supposed to be the second factor is the thing that has been
  copied.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias NerdMeet.Accounts.AuthEvent
  alias NerdMeet.Accounts.Credential
  alias NerdMeet.Accounts.IdentityProvider
  alias NerdMeet.Accounts.Risk
  alias NerdMeet.Accounts.User
  alias NerdMeet.Accounts.WebAuthn
  alias NerdMeet.Repo

  @spec get_user(binary()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user_by_handle(binary()) :: User.t() | nil
  def get_user_by_handle(handle), do: Repo.get_by(User, handle: String.downcase(handle))

  @doc """
  Creates an account whose adulthood has already been proven.

  The provider call is deliberately the first statement and deliberately
  outside the `Multi` below it.
  """
  @spec register(map()) :: {:ok, User.t()} | {:error, atom() | Ecto.Changeset.t()}
  def register(%{"handle" => handle} = params) do
    identity_payload = Map.get(params, "identity", %{})

    case IdentityProvider.verify(identity_payload) do
      {:ok, identity} -> insert_verified_user(handle, identity)
      {:error, reason} -> {:error, reason}
    end
  end

  def register(_params), do: {:error, :invalid_params}

  defp insert_verified_user(handle, identity) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.insert(
      :user,
      User.registration_changeset(%User{}, %{
        handle: handle,
        birth_year: identity.birth_year,
        prefecture: identity.prefecture,
        identity_serial_hash: identity.serial_hash
      })
    )
    |> Multi.update(:verified, fn %{user: user} ->
      User.verification_changeset(user, %{
        verified_at: now,
        birth_year: identity.birth_year,
        prefecture: identity.prefecture,
        identity_serial_hash: identity.serial_hash,
        status: "active"
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{verified: user}} -> {:ok, user}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @spec list_credentials(binary()) :: [Credential.t()]
  def list_credentials(user_id) do
    Repo.all(
      from c in Credential,
        where: c.user_id == ^user_id and is_nil(c.revoked_at),
        order_by: [asc: c.inserted_at]
    )
  end

  @spec add_credential(binary(), map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def add_credential(user_id, attrs) do
    %Credential{}
    |> Credential.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Verifies an assertion, scores the attempt and records what was decided.

  Returns `{:ok, user, assessment}` when the session may proceed,
  `{:step_up, user, assessment}` when it may proceed only after a second
  factor, and `{:error, reason}` otherwise. `{:error, :credential_cloned}` has
  already revoked every credential on the account by the time it is returned.
  """
  @spec authenticate(binary(), WebAuthn.assertion(), WebAuthn.expectation(), Risk.context()) ::
          {:ok, User.t(), Risk.assessment()}
          | {:step_up, User.t(), Risk.assessment()}
          | {:error, atom()}
  def authenticate(credential_id, assertion, expectation, context \\ %{}) do
    with {:ok, credential} <- fetch_credential(credential_id),
         {:ok, %{sign_count: sign_count}} <-
           WebAuthn.verify(credential.public_key, credential.cose_alg, assertion, expectation),
         :ok <- check_counter(credential, sign_count) do
      user = Repo.get!(User, credential.user_id)
      assessment = Risk.assess(user, context, last_event(user.id))

      Repo.update!(Credential.used_changeset(credential, sign_count))
      record_event(user, context, assessment.score, to_string(assessment.decision), assessment.reasons)
      Repo.update!(User.location_changeset(user, location_attrs(context)))

      case assessment.decision do
        :allow -> {:ok, user, assessment}
        :step_up -> {:step_up, user, assessment}
      end
    end
  end

  @doc """
  Revokes every credential on an account.

  Used when an authenticator turns out to have been cloned, and available to
  members directly, because "I think someone has my key" should not require a
  support ticket.
  """
  @spec revoke_all_credentials(binary(), binary()) :: {non_neg_integer(), nil}
  def revoke_all_credentials(user_id, reason) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(c in Credential, where: c.user_id == ^user_id and is_nil(c.revoked_at)),
      set: [revoked_at: now, revoked_reason: reason, updated_at: now]
    )
  end

  @spec list_auth_events(binary(), pos_integer()) :: [AuthEvent.t()]
  def list_auth_events(user_id, limit \\ 20) do
    Repo.all(
      from e in AuthEvent,
        where: e.user_id == ^user_id,
        order_by: [desc: e.occurred_at],
        limit: ^limit
    )
  end

  @doc "Marks an account suspended without deleting anything."
  @spec suspend(User.t(), binary()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def suspend(%User{} = user, reason) do
    revoke_all_credentials(user.id, reason)
    Repo.update(User.status_changeset(user, "suspended"))
  end

  defp fetch_credential(credential_id) do
    case Repo.get_by(Credential, credential_id: credential_id) do
      nil -> {:error, :unknown_credential}
      %Credential{revoked_at: %DateTime{}} -> {:error, :credential_revoked}
      credential -> {:ok, credential}
    end
  end

  # A counter that stayed put or went backwards means two copies of the same
  # key material exist. Zero is the documented "this authenticator does not
  # count" value and is left alone.
  defp check_counter(%Credential{sign_count: 0}, 0), do: :ok

  defp check_counter(%Credential{} = credential, sign_count) do
    if sign_count > credential.sign_count do
      :ok
    else
      user = Repo.get!(User, credential.user_id)
      revoke_all_credentials(credential.user_id, "signature counter regression")

      record_event(user, %{}, 100, "revoke_all", ["credential_cloned"])
      {:error, :credential_cloned}
    end
  end

  defp last_event(user_id) do
    Repo.one(
      from e in AuthEvent,
        where: e.user_id == ^user_id and e.decision != "revoke_all",
        order_by: [desc: e.occurred_at],
        limit: 1
    )
  end

  defp record_event(user, context, score, decision, reasons) do
    %AuthEvent{}
    |> AuthEvent.changeset(%{
      user_id: user.id,
      kind: "authentication",
      country: Map.get(context, :country),
      latitude: Map.get(context, :latitude),
      longitude: Map.get(context, :longitude),
      risk_score: score,
      decision: decision,
      reasons: %{"list" => reasons},
      occurred_at: Map.get(context, :at) || DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp location_attrs(context) do
    %{
      last_country: Map.get(context, :country),
      last_latitude: Map.get(context, :latitude),
      last_longitude: Map.get(context, :longitude),
      last_seen_at: Map.get(context, :at) || DateTime.utc_now()
    }
  end
end
