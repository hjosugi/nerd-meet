defmodule NerdMeet.Members do
  @moduledoc """
  Profiles, saved queries, and the directory search that runs over them.

  The directory never returns raw profile rows. Everything that leaves this
  context has been through `NerdMeet.Privacy.Anonymity`, because a search
  result set is exactly the shape of data that re-identifies people when it is
  published at full precision.
  """

  import Ecto.Query, warn: false

  alias NerdMeet.Members.Profile
  alias NerdMeet.Members.RegionTable
  alias NerdMeet.Members.SavedQuery
  alias NerdMeet.Members.Search
  alias NerdMeet.Privacy.Anonymity
  alias NerdMeet.Repo

  @known_languages ~w(
    elixir erlang go rust ruby python javascript typescript java kotlin swift
    scala clojure haskell ocaml c cpp csharp php perl lua zig nim julia r sql
  )

  @doc "Languages a profile may claim. Kept closed so search stays comparable."
  @spec known_languages() :: [binary()]
  def known_languages, do: @known_languages

  @spec region_for(binary()) :: binary()
  def region_for(prefecture), do: Anonymity.region(prefecture)

  @spec prefectures() :: [binary()]
  def prefectures, do: RegionTable.prefectures()

  @spec get_profile(binary()) :: Profile.t() | nil
  def get_profile(user_id), do: Repo.get_by(Profile, user_id: user_id)

  @spec upsert_profile(binary(), map()) :: {:ok, Profile.t()} | {:error, Ecto.Changeset.t()}
  def upsert_profile(user_id, attrs) do
    case_result =
      case get_profile(user_id) do
        nil -> %Profile{}
        existing -> existing
      end

    case_result
    |> Profile.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
  end

  @spec change_profile(Profile.t(), map()) :: Ecto.Changeset.t()
  def change_profile(%Profile{} = profile, attrs \\ %{}), do: Profile.changeset(profile, attrs)

  @doc """
  Runs a filter against the directory and anonymises the result.

  `:viewer_id` is excluded from results, and so is anyone in a block
  relationship with the viewer, in either direction.
  """
  @spec search(map(), keyword()) :: %{
          rows: [map()],
          suppressed: non_neg_integer(),
          by_band: map(),
          k: pos_integer()
        }
  def search(filter, opts \\ []) do
    filter
    |> Search.to_query()
    |> exclude_viewer(opts[:viewer_id])
    |> exclude_hidden_accounts()
    |> limit(^Keyword.get(opts, :limit, 500))
    |> Repo.all()
    |> Enum.map(&directory_row/1)
    |> Anonymity.anonymize(opts)
  end

  @doc """
  Every profile eligible for the public directory, as anonymisable rows.
  """
  @spec directory_rows() :: [map()]
  def directory_rows do
    from(p in Profile, where: p.visibility == "directory")
    |> exclude_hidden_accounts()
    |> Repo.all()
    |> Enum.map(&directory_row/1)
  end

  @doc "Saved queries belonging to a user."
  @spec list_saved_queries(binary()) :: [SavedQuery.t()]
  def list_saved_queries(user_id) do
    Repo.all(from q in SavedQuery, where: q.user_id == ^user_id, order_by: [desc: q.inserted_at])
  end

  @spec create_saved_query(binary(), map()) ::
          {:ok, SavedQuery.t()} | {:error, Ecto.Changeset.t()}
  def create_saved_query(user_id, attrs) do
    %SavedQuery{}
    |> SavedQuery.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc "The query a member has chosen to show on their profile, if any."
  @spec published_query(binary()) :: SavedQuery.t() | nil
  def published_query(user_id) do
    Repo.one(
      from q in SavedQuery,
        where: q.user_id == ^user_id and q.published,
        order_by: [desc: q.updated_at],
        limit: 1
    )
  end

  @doc "Renders a saved query as readable SQL."
  @spec render_sql(SavedQuery.t() | map()) :: binary()
  def render_sql(%SavedQuery{filter: filter}), do: Search.to_sql(filter)
  def render_sql(filter) when is_map(filter), do: Search.to_sql(filter)

  @doc """
  Finds people whose published condition you satisfy, and who satisfy yours.

  This is the feature that only makes sense in this product. A one-way search
  tells you who fits what you want. Comparing two published conditions tells
  you who fits what you want *and* wants what you are, before either of you
  has spent anything on finding out.
  """
  @spec mutual_query_matches(binary(), keyword()) :: [
          %{user_id: binary(), profile: Profile.t(), their_query: SavedQuery.t()}
        ]
  def mutual_query_matches(user_id, opts \\ []) do
    with %Profile{} = mine <- get_profile(user_id),
         %SavedQuery{} = my_query <- published_query(user_id) do
      limit = Keyword.get(opts, :limit, 50)

      from(q in SavedQuery,
        join: p in Profile,
        on: p.user_id == q.user_id,
        where: q.published and q.user_id != ^user_id and p.visibility == "directory",
        select: {q, p}
      )
      |> Repo.all()
      |> Enum.filter(fn {their_query, their_profile} ->
        Search.matches?(their_profile, my_query.filter) and
          Search.matches?(mine, their_query.filter)
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {their_query, their_profile} ->
        %{user_id: their_profile.user_id, profile: their_profile, their_query: their_query}
      end)
    else
      _missing -> []
    end
  end

  defp directory_row(%Profile{} = profile) do
    %{
      user_id: profile.user_id,
      display_name: profile.display_name,
      headline: profile.headline,
      prefecture: profile.prefecture,
      birth_year: profile.birth_year,
      years_experience: profile.years_experience,
      remote_ok: profile.remote_ok,
      languages: profile.languages,
      skills: profile.skills,
      tools: profile.tools
    }
  end

  defp exclude_viewer(query, nil), do: query
  defp exclude_viewer(query, viewer_id), do: where(query, [p], p.user_id != ^viewer_id)

  # A shadow-limited or suspended account stays reachable by direct link for
  # the people it already matched with, and disappears from every listing.
  defp exclude_hidden_accounts(query) do
    restricted =
      from e in NerdMeet.Moderation.Enforcement,
        where: e.kind in ["shadow_limit", "suspension"] and is_nil(e.lifted_at),
        select: e.user_id

    from p in query,
      join: u in NerdMeet.Accounts.User,
      on: u.id == p.user_id,
      where: u.status == "active" and is_nil(u.deleted_at),
      where: p.user_id not in subquery(restricted)
  end
end
