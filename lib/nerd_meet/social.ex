defmodule NerdMeet.Social do
  @moduledoc """
  Likes, matches, blocks and reports.

  A match is the only thing that opens a conversation. That single rule does
  more against unsolicited contact than any amount of message filtering: an
  operator has to be chosen back before they can say anything at all, which
  turns a broadcast into a funnel they cannot widen.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias NerdMeet.Repo
  alias NerdMeet.Social.Block
  alias NerdMeet.Social.Like
  alias NerdMeet.Social.Match
  alias NerdMeet.Social.Report

  @doc """
  Records a like, creating the match if it is now mutual.

  Both statements run in one transaction so that two people liking each other
  at the same moment produce one match rather than two or none.
  """
  @spec like(binary(), binary()) ::
          {:ok, %{like: Like.t(), match: Match.t() | nil}} | {:error, atom() | Ecto.Changeset.t()}
  def like(from_user_id, to_user_id) do
    cond do
      from_user_id == to_user_id ->
        {:error, :self_like}

      blocked_either_way?(from_user_id, to_user_id) ->
        {:error, :blocked}

      true ->
        Multi.new()
        |> Multi.insert(
          :like,
          Like.changeset(%Like{}, %{from_user_id: from_user_id, to_user_id: to_user_id}),
          on_conflict: :nothing,
          conflict_target: [:from_user_id, :to_user_id]
        )
        |> Multi.run(:match, fn repo, _changes ->
          if reciprocated?(repo, from_user_id, to_user_id) do
            create_match(repo, from_user_id, to_user_id)
          else
            {:ok, nil}
          end
        end)
        |> Repo.transaction()
        |> case do
          {:ok, result} -> {:ok, result}
          {:error, _step, reason, _changes} -> {:error, reason}
        end
    end
  end

  @spec liked?(binary(), binary()) :: boolean()
  def liked?(from_user_id, to_user_id) do
    Repo.exists?(from l in Like, where: l.from_user_id == ^from_user_id and l.to_user_id == ^to_user_id)
  end

  @doc "The match between two people, if there is one."
  @spec get_match(binary(), binary()) :: Match.t() | nil
  def get_match(user_id, other_id) do
    {a, b} = Match.order(user_id, other_id)
    Repo.get_by(Match, user_a_id: a, user_b_id: b)
  end

  @spec matched?(binary(), binary()) :: boolean()
  def matched?(user_id, other_id) do
    case get_match(user_id, other_id) do
      %Match{closed_at: nil} -> true
      _other -> false
    end
  end

  @spec list_matches(binary()) :: [Match.t()]
  def list_matches(user_id) do
    Repo.all(
      from m in Match,
        where: (m.user_a_id == ^user_id or m.user_b_id == ^user_id) and is_nil(m.closed_at),
        order_by: [desc: m.matched_at]
    )
  end

  @doc "The other participant in a match."
  @spec counterpart(Match.t(), binary()) :: binary()
  def counterpart(%Match{user_a_id: a, user_b_id: b}, user_id), do: if(a == user_id, do: b, else: a)

  @doc """
  Blocks someone, in both directions and for good.

  A block also closes any match between the pair, so the conversation stops
  existing rather than merely refusing new messages.
  """
  @spec block(binary(), binary(), binary() | nil) ::
          {:ok, Block.t()} | {:error, Ecto.Changeset.t()}
  def block(blocker_id, blocked_id, reason \\ nil) do
    result =
      %Block{}
      |> Block.changeset(%{blocker_id: blocker_id, blocked_id: blocked_id, reason: reason})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:blocker_id, :blocked_id])

    with {:ok, _block} <- result do
      close_match(blocker_id, blocked_id)
    end

    result
  end

  @spec blocked_either_way?(binary(), binary()) :: boolean()
  def blocked_either_way?(a, b) do
    Repo.exists?(
      from x in Block,
        where:
          (x.blocker_id == ^a and x.blocked_id == ^b) or
            (x.blocker_id == ^b and x.blocked_id == ^a)
    )
  end

  @spec report(binary() | nil, binary(), binary(), keyword()) ::
          {:ok, Report.t()} | {:error, Ecto.Changeset.t()}
  def report(reporter_id, subject_id, reason, opts \\ []) do
    %Report{}
    |> Report.changeset(%{
      reporter_id: reporter_id,
      subject_id: subject_id,
      reason: reason,
      body: Keyword.get(opts, :body),
      message_id: Keyword.get(opts, :message_id)
    })
    |> Repo.insert()
  end

  @doc "How many distinct people have reported an account."
  @spec report_count(binary()) :: non_neg_integer()
  def report_count(subject_id) do
    Repo.one(
      from r in Report,
        where: r.subject_id == ^subject_id,
        select: count(fragment("DISTINCT ?", r.reporter_id))
    ) || 0
  end

  defp reciprocated?(repo, from_user_id, to_user_id) do
    repo.exists?(from l in Like, where: l.from_user_id == ^to_user_id and l.to_user_id == ^from_user_id)
  end

  defp create_match(repo, from_user_id, to_user_id) do
    {a, b} = Match.order(from_user_id, to_user_id)

    %Match{}
    |> Match.changeset(%{user_a_id: a, user_b_id: b, matched_at: DateTime.utc_now()})
    |> repo.insert(on_conflict: :nothing, conflict_target: [:user_a_id, :user_b_id])
    |> case do
      {:ok, %Match{id: nil}} -> {:ok, repo.get_by(Match, user_a_id: a, user_b_id: b)}
      other -> other
    end
  end

  defp close_match(a, b) do
    {left, right} = Match.order(a, b)

    Repo.update_all(
      from(m in Match,
        where: m.user_a_id == ^left and m.user_b_id == ^right and is_nil(m.closed_at)
      ),
      set: [closed_at: DateTime.utc_now()]
    )
  end
end
