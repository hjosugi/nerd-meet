defmodule NerdMeet.Repo.Migrations.CreateSavedQueries do
  use Ecto.Migration

  def change do
    create table(:saved_queries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :string

      # A structured predicate, never raw SQL from a user. It is rendered as
      # SQL for people to read and compiled to Ecto for execution.
      add :filter, :map, null: false, default: %{}

      # A published query is attached to the owner's profile: "this is what I
      # am looking for", written as a condition rather than a paragraph.
      add :published, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:saved_queries, [:user_id])
    create index(:saved_queries, [:published])
  end
end
