defmodule NerdMeet.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  def change do
    create table(:profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :display_name, :string, null: false
      add :headline, :string
      add :bio, :text

      # Quasi-identifiers. Every one of these is banded before it reaches the
      # directory; see NerdMeet.Privacy.Anonymity.
      add :birth_year, :integer
      add :prefecture, :string
      add :region, :string
      add :years_experience, :integer

      add :remote_ok, :boolean, null: false, default: false
      add :languages, {:array, :string}, null: false, default: []
      add :skills, {:array, :string}, null: false, default: []
      add :tools, {:array, :string}, null: false, default: []

      add :github_handle, :string
      add :blog_url, :string

      # "directory" is listed and searchable, "matches_only" is visible to
      # people you already matched with, "hidden" is nowhere.
      add :visibility, :string, null: false, default: "directory"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:profiles, [:user_id])
    create index(:profiles, [:visibility])
    create index(:profiles, [:prefecture])
    create index(:profiles, [:skills], using: "GIN")
  end
end
