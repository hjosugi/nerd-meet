defmodule NerdMeet.Workers.BuildSnapshot do
  @moduledoc "Regenerates the public directory snapshot."
  use Oban.Worker, queue: :snapshots, max_attempts: 3

  alias NerdMeet.Publishing

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {:ok, _snapshot, _path} = Publishing.generate(slug: Map.get(args, "slug", "directory"))
    :ok
  end
end
