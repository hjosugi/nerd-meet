defmodule Mix.Tasks.Nerd.Snapshot do
  @shortdoc "Builds the anonymised static directory snapshot"
  @moduledoc """
  Regenerates the public directory snapshot and prints what it disclosed.

      $ mix nerd.snapshot

  The suppressed count is the number worth watching. A directory that
  suppresses most of its rows has not been made private; it has been made
  useless, and the fix is coarser bands rather than a smaller k.
  """
  use Mix.Task

  alias NerdMeet.Publishing

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    slug = List.first(args) || "directory"
    {:ok, snapshot, path} = Publishing.generate(slug: slug)

    Mix.shell().info("""
    snapshot   #{snapshot.slug}
    path       #{path}
    rows       #{snapshot.record_count}
    suppressed #{snapshot.suppressed_count}
    k          #{snapshot.k}
    size       #{Float.round(snapshot.byte_size / 1024, 1)} KB
    sha256     #{snapshot.checksum}
    """)
  end
end
