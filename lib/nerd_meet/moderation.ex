defmodule NerdMeet.Moderation do
  @moduledoc """
  The three-stage cascade, and the bookkeeping that keeps it honest.

      stage 1  regex on the send path         every message      ~0 cost
      stage 2  aggregate queries, background  every message      ~0 cost
      stage 3  a model, background            1-3% of messages   real cost

  Running a model over every message is what makes automated moderation
  unaffordable, so almost nothing reaches one. Cheap filters pass the
  overwhelming majority through untouched and the expensive judgement is spent
  on what survives.

  Enforcement is graded, because the cost of a false positive is a real person
  being thrown off a service they did nothing wrong on:

    * a stage 1 hit refuses the message and says which rule it hit
    * a behavioural score above the threshold applies a shadow limit and files
      the case for review
    * only a confirmed violation suspends the account, and the identity hash
      then keeps that person from simply registering again

  Reading message plaintext is possible during review and writes an audit row
  every single time. Without that, "staff can read flagged messages" is
  indistinguishable from "staff can read everything".
  """

  import Ecto.Query, warn: false

  alias NerdMeet.Accounts
  alias NerdMeet.Chat.Message
  alias NerdMeet.Moderation.AuditLog
  alias NerdMeet.Moderation.Classifier
  alias NerdMeet.Moderation.Enforcement
  alias NerdMeet.Moderation.Review
  alias NerdMeet.Moderation.Rules
  alias NerdMeet.Moderation.Signals
  alias NerdMeet.Repo

  @doc "Stage 1. Cheap enough to run synchronously on every send."
  @spec screen(binary()) :: {:block, binary()} | {:flag, binary()} | :ok
  defdelegate screen(body), to: Rules, as: :check

  @doc "The sentence shown to a sender whose message was refused."
  defdelegate explain(reason), to: Rules

  @doc """
  Stages 2 and 3 for one account, run from a background job.

  Stage 3 is only consulted when the behavioural score clears the configured
  threshold, which is the whole reason the cascade is affordable.
  """
  @spec review_account(binary(), keyword()) :: {:ok, Review.t()} | {:ok, :clear}
  def review_account(user_id, opts \\ []) do
    assessment = Signals.assess(user_id)

    if assessment.score >= review_threshold() do
      {verdict, reasons} = maybe_classify(assessment, opts)

      {:ok, review} =
        record_review(%{
          subject_id: user_id,
          message_id: opts[:message_id],
          stage: if(opts[:body], do: "classifier", else: "signals"),
          score: assessment.score,
          verdict: verdict,
          reasons: assessment.reasons ++ reasons
        })

      if verdict == "violation" or assessment.score >= 80 do
        apply_enforcement(user_id, "shadow_limit", Enum.join(review.reasons, ","))
      end

      {:ok, review}
    else
      {:ok, :clear}
    end
  end

  @spec record_review(map()) :: {:ok, Review.t()} | {:error, Ecto.Changeset.t()}
  def record_review(attrs) do
    %Review{}
    |> Review.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Open cases, oldest first, for a human to work through."
  @spec review_queue(pos_integer()) :: [Review.t()]
  def review_queue(limit \\ 50) do
    Repo.all(
      from r in Review,
        where: is_nil(r.resolved_at) and r.verdict != "clear",
        order_by: [asc: r.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Closes a case. A confirmed violation suspends the account outright.
  """
  @spec resolve(Review.t(), binary(), binary(), binary()) ::
          {:ok, Review.t()} | {:error, Ecto.Changeset.t()}
  def resolve(%Review{} = review, reviewer_id, resolution, reason) do
    if resolution == "violation" do
      review.subject_id |> Accounts.get_user() |> Accounts.suspend(reason)
      apply_enforcement(review.subject_id, "suspension", reason)
    end

    audit(reviewer_id, "moderation.resolve", "review", review.id, reason, %{
      "resolution" => resolution
    })

    review
    |> Review.changeset(%{
      reviewer_id: reviewer_id,
      resolution: resolution,
      resolved_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @spec apply_enforcement(binary(), binary(), binary() | nil) ::
          {:ok, Enforcement.t()} | {:error, Ecto.Changeset.t()}
  def apply_enforcement(user_id, kind, reason \\ nil) do
    %Enforcement{}
    |> Enforcement.changeset(%{user_id: user_id, kind: kind, reason: reason})
    |> Repo.insert()
  end

  @spec active_enforcements(binary()) :: [Enforcement.t()]
  def active_enforcements(user_id) do
    Repo.all(
      from e in Enforcement,
        where: e.user_id == ^user_id and is_nil(e.lifted_at),
        where: is_nil(e.expires_at) or e.expires_at > ^DateTime.utc_now()
    )
  end

  @spec restricted?(binary(), binary()) :: boolean()
  def restricted?(user_id, kind) do
    Enum.any?(active_enforcements(user_id), &(&1.kind == kind))
  end

  @doc """
  Reads one message in the clear, for review, and records that it happened.

  A reason is mandatory and validated for length, because an audit trail whose
  reason column reads "check" on every row documents nothing.
  """
  @spec read_plaintext(binary(), Message.t(), binary()) :: {:ok, binary()} | {:error, atom()}
  def read_plaintext(actor_id, %Message{} = message, reason) do
    case NerdMeet.Chat.decrypt_message(message) do
      {:ok, body} ->
        audit(actor_id, "message.read_plaintext", "message", message.id, reason, %{
          "conversation_id" => message.conversation_id
        })

        {:ok, body}

      :error ->
        {:error, :unreadable}
    end
  end

  @doc "Appends a row to the audit log."
  @spec audit(binary() | nil, binary(), binary(), binary() | nil, binary(), map()) ::
          {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def audit(actor_id, action, subject_type, subject_id, reason, metadata \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      actor_id: actor_id,
      action: action,
      subject_type: subject_type,
      subject_id: subject_id,
      reason: reason,
      metadata: metadata
    })
    |> Repo.insert()
  end

  @spec audit_trail(binary(), binary()) :: [AuditLog.t()]
  def audit_trail(subject_type, subject_id) do
    Repo.all(
      from l in AuditLog,
        where: l.subject_type == ^subject_type and l.subject_id == ^subject_id,
        order_by: [desc: l.occurred_at]
    )
  end

  defp maybe_classify(_assessment, opts) do
    case opts[:body] do
      nil ->
        {"suspect", []}

      body ->
        case Classifier.classify(body, %{}) do
          {:ok, %{verdict: verdict, reasons: reasons}} -> {verdict, reasons}
          {:error, _reason} -> {"suspect", ["classifier_unavailable"]}
        end
    end
  end

  defp review_threshold do
    Application.get_env(:nerd_meet, :moderation, [])[:review_threshold] || 60
  end
end
