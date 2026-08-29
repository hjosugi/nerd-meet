defmodule NerdMeet.Release do
  @moduledoc """
  Tasks that have to run in a release, where Mix is not available.

  Migrations are deliberately a separate command rather than something the
  application runs at boot. A schema change that fails should stop a deploy,
  not take down the running system.
  """
  @app :nerd_meet

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _result, _apps} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc "Regenerates the public directory snapshot from a release."
  def snapshot do
    load_app()
    Application.ensure_all_started(@app)
    {:ok, snapshot, path} = NerdMeet.Publishing.generate()
    IO.puts("snapshot #{snapshot.record_count} rows -> #{path}")
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.load(@app)
  end
end
