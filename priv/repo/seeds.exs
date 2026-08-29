# Development data. Run with `mix run priv/repo/seeds.exs`, or as part of
# `mix setup`.
#
# Everything here goes through the same context functions the application uses,
# so seeding exercises identity verification, profile validation and the search
# DSL rather than writing rows behind their backs.

alias NerdMeet.Members
alias NerdMeet.Repo
alias NerdMeet.Social

if Repo.aggregate(NerdMeet.Accounts.User, :count) > 0 do
  IO.puts("seeds: users already present, skipping")
else
  people = [
    {"hjosugi", "東京都", 1988, 12, ["elixir", "go"], ["postgresql", "kubernetes"], "分散システムとデータ基盤"},
    {"mnakamura", "神奈川県", 1992, 8, ["elixir", "typescript"], ["phoenix", "liveview"], "フロントエンドとBFF"},
    {"ksato", "大阪府", 1985, 15, ["rust", "c"], ["linux", "ebpf"], "低レイヤとパフォーマンス"},
    {"ytanaka", "東京都", 1994, 6, ["python", "sql"], ["dbt", "airflow"], "データエンジニアリング"},
    {"rsuzuki", "福岡県", 1990, 10, ["elixir", "erlang"], ["otp", "postgresql"], "OTPとリアルタイム系"},
    {"aokada", "北海道", 1996, 4, ["typescript", "go"], ["nextjs", "grpc"], "プロダクト開発"}
  ]

  users =
    Enum.map(people, fn {handle, prefecture, birth_year, experience, languages, skills, headline} ->
      {:ok, user} =
        NerdMeet.Accounts.register(%{
          "handle" => handle,
          "identity" => %{
            "serial" => "seed-#{handle}",
            "birth_year" => birth_year,
            "prefecture" => prefecture
          }
        })

      {:ok, _profile} =
        Members.upsert_profile(user.id, %{
          display_name: handle,
          headline: headline,
          birth_year: birth_year,
          prefecture: prefecture,
          years_experience: experience,
          remote_ok: true,
          languages: languages,
          skills: skills
        })

      {:ok, _query} =
        Members.create_saved_query(user.id, %{
          name: "経験5年以上・リモート可",
          description: "一緒に設計の話ができる人",
          published: true,
          filter: %{
            "all" => [
              %{"field" => "years_experience", "op" => "gte", "value" => 5},
              %{"field" => "remote_ok", "op" => "eq", "value" => true}
            ]
          }
        })

      user
    end)

  # One mutual like so there is a conversation to open.
  [first, second | _rest] = users
  {:ok, _a} = Social.like(first.id, second.id)
  {:ok, _b} = Social.like(second.id, first.id)

  {:ok, snapshot, path} = NerdMeet.Publishing.generate(k: 1)

  IO.puts("""
  seeds: #{length(users)} members created
  seeds: #{first.handle} and #{second.handle} are matched
  seeds: snapshot #{snapshot.record_count} rows -> #{path}
  seeds: sign in during development with /dev/session/#{first.handle}
  """)
end
