defmodule NerdMeet.Accounts.Credential do
  @moduledoc """
  One registered authenticator (a passkey).

  `sign_count` is the interesting column. An authenticator increments it on
  every assertion, so a value that fails to advance means the key material has
  been copied out of the device it was supposed to be locked inside.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :credential_id, :binary
    field :public_key, :binary
    field :cose_alg, :integer
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :nickname, :string
    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_reason, :string

    belongs_to :user, NerdMeet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :credential_id,
      :public_key,
      :cose_alg,
      :sign_count,
      :aaguid,
      :nickname
    ])
    |> validate_required([:user_id, :credential_id, :public_key, :cose_alg])
    |> validate_inclusion(:cose_alg, [-7, -8])
    |> unique_constraint(:credential_id)
  end

  @doc false
  def used_changeset(credential, sign_count) do
    change(credential, sign_count: sign_count, last_used_at: DateTime.utc_now())
  end

  @doc false
  def revoke_changeset(credential, reason) do
    change(credential, revoked_at: DateTime.utc_now(), revoked_reason: reason)
  end
end
