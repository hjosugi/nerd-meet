defmodule Mix.Tasks.Nerd.Demo do
  @shortdoc "Seeds synthetic members to explore the anonymity density effect"
  @moduledoc """
  Generates synthetic directory rows and reports what k-anonymity does to them.

      $ mix nerd.demo 300
      $ mix nerd.demo 5000

  Run it at both sizes. At a few hundred rows nearly everything is suppressed
  or pushed to the coarsest band; at a few thousand the same code publishes
  most rows at full precision. Nothing changed but the population, which is the
  point: k-anonymity has a density requirement, and a young directory has to
  start coarse.
  """
  use Mix.Task

  alias NerdMeet.Privacy.Anonymity

  # Roughly how Japanese software engineers actually distribute.
  @prefecture_weights [
    {"東京都", 34},
    {"神奈川県", 12},
    {"大阪府", 9},
    {"愛知県", 7},
    {"埼玉県", 6},
    {"千葉県", 6},
    {"福岡県", 5},
    {"兵庫県", 4},
    {"京都府", 3},
    {"北海道", 3},
    {"宮城県", 2},
    {"広島県", 2},
    {"静岡県", 2},
    {"新潟県", 1},
    {"沖縄県", 1},
    {"長野県", 1},
    {"岡山県", 1},
    {"熊本県", 1}
  ]

  @impl Mix.Task
  def run(args) do
    count = args |> List.first() |> parse_count()
    report = count |> synthetic_rows() |> Anonymity.analyze()

    Mix.shell().info("""
    population      #{report.total}
    published rows  #{report.published}
    suppressed      #{report.suppressed}
    published       #{Float.round(report.published_ratio * 100, 1)}%
    full precision  #{Float.round(report.fine_ratio * 100, 1)}%
    k violations    #{report.violations}
    by band         #{inspect(report.by_band)}
    """)
  end

  @doc """
  Deterministic synthetic rows, so two runs are comparable.

  The distribution is deliberately skewed rather than uniform. Real member
  populations pile up in a few prefectures and a narrow age range, and a
  uniform generator would make k-anonymity look far worse than it is: spread
  evenly over 47 prefectures, no directory of any plausible size ever fills a
  fine-band group.
  """
  @spec synthetic_rows(pos_integer()) :: [map()]
  def synthetic_rows(count) do
    Enum.map(1..count, fn i ->
      %{
        user_id: "synthetic-#{i}",
        display_name: "member#{i}",
        prefecture: pick(@prefecture_weights, rand(i, 1)),
        birth_year: 1980 + rem(rand(i, 2), 17),
        years_experience: 2 + rem(rand(i, 3), 18),
        remote_ok: rem(rand(i, 4), 3) == 0,
        languages: [],
        skills: [],
        tools: []
      }
    end)
  end

  # A hash rather than a linear step. A linear congruential generator taken
  # modulo a small number produces a short cycle, which quietly collapses the
  # variety this demo exists to show.
  defp rand(index, salt), do: :erlang.phash2({index, salt}, 1_000_000)

  defp pick(weights, value) do
    target = rem(value, 100)

    weights
    |> Enum.reduce_while({target, "東京都"}, fn {prefecture, weight}, {remaining, _last} ->
      if remaining < weight,
        do: {:halt, {remaining, prefecture}},
        else: {:cont, {remaining - weight, prefecture}}
    end)
    |> elem(1)
  end

  defp parse_count(nil), do: 300

  defp parse_count(arg) do
    case Integer.parse(arg) do
      {count, _rest} when count > 0 -> count
      _invalid -> 300
    end
  end
end
