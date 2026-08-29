defmodule NerdMeet.Repo.Migrations.AddObanJobs do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  # Rolling all the way back destroys the job history, so stop at version 1.
  def down, do: Oban.Migration.down(version: 1)
end
