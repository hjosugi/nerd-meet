defmodule NerdMeet.Repo.Migrations.CreateModeration do
  use Ecto.Migration

  def change do
    create table(:moderation_reviews, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all)
      add :subject_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # "rules", "signals" or "classifier" — which stage of the cascade
      # produced this row.
      add :stage, :string, null: false
      add :score, :integer, null: false, default: 0
      add :verdict, :string, null: false
      add :reasons, {:array, :string}, null: false, default: []

      add :reviewer_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime_usec
      add :resolution, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:moderation_reviews, [:subject_id])
    create index(:moderation_reviews, [:stage, :verdict])
    create index(:moderation_reviews, [:resolved_at])

    # A shadow limit keeps an account working while removing it from search.
    # The point is that a spam operator does not learn it has been caught.
    create table(:enforcements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :reason, :string
      add :expires_at, :utc_datetime_usec
      add :lifted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:enforcements, [:user_id, :kind])
  end
end
