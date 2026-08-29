defmodule NerdMeet.Moderation.Signals do
  @moduledoc """
  Stage 2: behaviour, not content.

  This stage reads no message text and costs nothing but a few aggregate
  queries, and it is the stage that actually catches operators. What someone
  writes can be rephrased indefinitely; how they behave cannot. An operator
  messages far more people than a member does, sends near-identical text, opens
  every conversation within seconds of matching, and collects reports. None of
  that is visible in any single message.

  Similarity is measured over `NerdMeet.Vault.fingerprint/1` digests, so
  "is this person pasting the same thing at everyone" is answered without
  anything being able to read what the thing says.
  """

  import Ecto.Query, warn: false

  alias NerdMeet.Chat.Message
  alias NerdMeet.Repo
  alias NerdMeet.Social
  alias NerdMeet.Vault

  # Fingerprints within this Hamming distance are treated as the same message
  # wearing a different hat. Short messages produce noisier digests than long
  # documents do, so the threshold is looser than SimHash literature suggests:
  # measured here, a reworded sentence lands around 14 and an unrelated one
  # around 27.
  @near_duplicate_distance 16
  @recent_window_hours 24
  @sample_size 40

  @type assessment :: %{score: non_neg_integer(), reasons: [binary()], metrics: map()}

  @doc """
  Scores an account's recent behaviour from 0 to 100.
  """
  @spec assess(binary()) :: assessment()
  def assess(user_id) do
    messages = recent_messages(user_id)

    metrics = %{
      fanout: fanout(messages),
      template_ratio: template_ratio(messages),
      instant_openers: instant_openers(user_id),
      reporters: Social.report_count(user_id),
      flagged_ratio: flagged_ratio(messages),
      sample: length(messages)
    }

    scored =
      Enum.filter(
        [
          {metrics.fanout >= 10, 30, "high_fanout"},
          {metrics.template_ratio >= 0.6 and metrics.sample >= 5, 30, "templated_messages"},
          {metrics.instant_openers >= 3, 20, "instant_openers"},
          {metrics.reporters >= 3, 40, "reported_by_many"},
          {metrics.flagged_ratio >= 0.3 and metrics.sample >= 5, 20, "repeated_rule_hits"}
        ],
        fn {hit?, _points, _reason} -> hit? end
      )

    %{
      score: scored |> Enum.map(fn {_hit, points, _reason} -> points end) |> Enum.sum() |> min(100),
      reasons: Enum.map(scored, fn {_hit, _points, reason} -> reason end),
      metrics: metrics
    }
  end

  @doc "Distinct conversations an account has written to in the window."
  @spec fanout([Message.t()]) :: non_neg_integer()
  def fanout(messages) do
    messages |> Enum.map(& &1.conversation_id) |> Enum.uniq() |> length()
  end

  @doc """
  The share of message pairs that are near-duplicates of each other.

  Comparing every pair is quadratic, which is fine at the sample size used here
  and is the reason the sample is capped.
  """
  @spec template_ratio([Message.t()]) :: float()
  def template_ratio(messages) do
    prints = messages |> Enum.map(& &1.fingerprint) |> Enum.reject(&is_nil/1)

    pairs =
      for {a, i} <- Enum.with_index(prints),
          {b, j} <- Enum.with_index(prints),
          i < j,
          do: Vault.similarity(a, b)

    case pairs do
      [] -> 0.0
      list -> Enum.count(list, &(&1 <= @near_duplicate_distance)) / length(list)
    end
  end

  @doc """
  How many conversations this account opened within a minute of matching.

  One is enthusiasm. Ten is a script.
  """
  @spec instant_openers(binary()) :: non_neg_integer()
  def instant_openers(user_id) do
    Repo.one(
      from m in Message,
        join: c in assoc(m, :conversation),
        join: mt in assoc(c, :match),
        where: m.sender_id == ^user_id,
        where: m.inserted_at <= datetime_add(mt.matched_at, 60, "second"),
        select: count(fragment("DISTINCT ?", c.id))
    ) || 0
  end

  defp flagged_ratio([]), do: 0.0

  defp flagged_ratio(messages) do
    Enum.count(messages, &(&1.moderation_state == "flagged")) / length(messages)
  end

  defp recent_messages(user_id) do
    since = DateTime.shift(DateTime.utc_now(), hour: -@recent_window_hours)

    Repo.all(
      from m in Message,
        where: m.sender_id == ^user_id and m.inserted_at >= ^since,
        order_by: [desc: m.inserted_at],
        limit: @sample_size,
        select: %{
          conversation_id: m.conversation_id,
          fingerprint: m.fingerprint,
          moderation_state: m.moderation_state,
          inserted_at: m.inserted_at
        }
    )
  end
end
