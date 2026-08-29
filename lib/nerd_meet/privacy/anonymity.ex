defmodule NerdMeet.Privacy.Anonymity do
  @moduledoc """
  k-anonymity for the public directory, with bands that widen on demand.

  Prefecture, birth year and years of experience are individually harmless and
  jointly identifying. Published together at full precision they routinely
  describe exactly one person, so the directory publishes bands instead.

  The part that only shows up once you run it: **k-anonymity has a density
  requirement.** Suppressing every group smaller than k is correct and, on a
  small population, catastrophic — at a few hundred members almost every
  combination is unique and the directory suppresses itself into uselessness.
  The answer is not to lower k. It is to start coarse and let precision arrive
  as the population does, which is what the ladder below implements: each row
  is published at the finest band whose group is still large enough, and only a
  row that is alone even at the coarsest band is withheld.

  `analyze/2` reports what happened, because "94% of rows kept detail" and
  "everything was suppressed" must never look the same from the outside.
  """

  @type band :: :fine | :medium | :coarse

  @regions_by_prefecture NerdMeet.Members.RegionTable.table()

  @doc """
  Bands a list of rows and drops those that cannot reach the k floor.

  Each row is a map with at least `:prefecture`, `:birth_year` and
  `:years_experience`. The returned rows carry `:band` plus the banded values,
  and no longer carry the exact ones.
  """
  @spec anonymize([map()], keyword()) :: %{
          rows: [map()],
          suppressed: non_neg_integer(),
          by_band: %{band() => non_neg_integer()},
          k: pos_integer()
        }
  def anonymize(rows, opts \\ []) do
    k = Keyword.get(opts, :k, configured_k())
    ladder = Keyword.get(opts, :ladder, configured_ladder())

    {published, remaining} =
      Enum.reduce(ladder, {[], rows}, fn band, {kept, pending} ->
        {ok, small} = split_by_k(pending, band, k)
        {kept ++ Enum.map(ok, &publish(&1, band)), small}
      end)

    %{
      rows: published,
      suppressed: length(remaining),
      by_band: Enum.frequencies_by(published, & &1.band),
      k: k
    }
  end

  @doc """
  Summarises an anonymisation without publishing it.

  Two ratios come back and they answer different questions.
  `published_ratio` is how much of the directory survived at all;
  `fine_ratio` is how much of it survived at full precision. A young directory
  publishes nearly everything and almost none of it finely, which is exactly
  the shape the density requirement predicts.
  """
  @spec analyze([map()], keyword()) :: %{
          total: non_neg_integer(),
          published: non_neg_integer(),
          suppressed: non_neg_integer(),
          published_ratio: float(),
          fine_ratio: float(),
          by_band: map(),
          violations: non_neg_integer(),
          k: pos_integer()
        }
  def analyze(rows, opts \\ []) do
    result = anonymize(rows, opts)
    total = length(rows)
    published = length(result.rows)

    %{
      total: total,
      published: published,
      suppressed: result.suppressed,
      published_ratio: ratio(published, total),
      fine_ratio: ratio(Map.get(result.by_band, :fine, 0), total),
      by_band: result.by_band,
      violations: violations(result.rows, result.k),
      k: result.k
    }
  end

  @doc """
  Counts published rows that sit in a group smaller than k.

  On correct output this is always zero. It exists so that a test can assert
  the property directly rather than trusting the implementation that produced
  it.
  """
  @spec violations([map()], pos_integer()) :: non_neg_integer()
  def violations(published_rows, k) do
    published_rows
    |> Enum.group_by(&{&1.band, &1.area, &1.age_band, &1.experience_band})
    |> Enum.reject(fn {_key, group} -> length(group) >= k end)
    |> Enum.map(fn {_key, group} -> length(group) end)
    |> Enum.sum()
  end

  defp ratio(_part, 0), do: 0.0
  defp ratio(part, total), do: part / total

  @doc "The quasi-identifier tuple a row would occupy at a given band."
  @spec key(map(), band()) :: {binary(), binary(), binary()}
  def key(row, band), do: {area(row, band), age_band(row, band), experience_band(row, band)}

  @doc "The region a prefecture belongs to."
  @spec region(binary() | nil) :: binary()
  def region(nil), do: "不明"
  def region(prefecture), do: Map.get(@regions_by_prefecture, prefecture, "不明")

  defp split_by_k(rows, band, k) do
    groups = Enum.group_by(rows, &key(&1, band))

    {big, small} = Enum.split_with(groups, fn {_key, group} -> length(group) >= k end)

    {Enum.flat_map(big, fn {_key, group} -> group end), Enum.flat_map(small, fn {_key, group} -> group end)}
  end

  defp publish(row, band) do
    row
    |> Map.drop([:prefecture, :birth_year, :years_experience])
    |> Map.merge(%{
      band: band,
      area: area(row, band),
      age_band: age_band(row, band),
      experience_band: experience_band(row, band)
    })
  end

  # Area widens prefecture into region and then into a single national bucket.
  defp area(row, :fine), do: row[:prefecture] || "不明"
  defp area(row, :medium), do: region(row[:prefecture])
  defp area(_row, :coarse), do: "日本"

  # Age widens from a five-year band to a decade to a career-stage label.
  defp age_band(row, band) do
    case {row[:birth_year], band} do
      {nil, _band} -> "不明"
      {year, :fine} -> decade_label(div(year, 5) * 5, 4)
      {year, :medium} -> decade_label(div(year, 10) * 10, 9)
      {year, :coarse} -> if year >= 1990, do: "1990年以降", else: "1989年以前"
    end
  end

  # Experience widens from two years to five to three named stages.
  defp experience_band(row, band) do
    case {row[:years_experience], band} do
      {nil, _band} -> "不明"
      {years, :fine} -> range_label(div(years, 2) * 2, 1)
      {years, :medium} -> range_label(div(years, 5) * 5, 4)
      {years, :coarse} when years < 3 -> "3年未満"
      {years, :coarse} when years < 10 -> "3〜9年"
      {_years, :coarse} -> "10年以上"
    end
  end

  defp decade_label(start, width), do: "#{start}〜#{start + width}年生まれ"
  defp range_label(start, width), do: "#{start}〜#{start + width}年"

  defp configured_k, do: Application.get_env(:nerd_meet, :privacy, [])[:k] || 5

  defp configured_ladder, do: Application.get_env(:nerd_meet, :privacy, [])[:band_ladder] || [:fine, :medium, :coarse]
end
