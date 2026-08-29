defmodule NerdMeet.Repo.Migrations.CreateSocial do
  use Ecto.Migration

  def change do
    create table(:likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :to_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:likes, [:from_user_id, :to_user_id])
    create index(:likes, [:to_user_id])
    create constraint(:likes, :likes_not_self, check: "from_user_id <> to_user_id")

    # user_a_id is always the smaller uuid, so a pair has exactly one row no
    # matter who liked first.
    create table(:matches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_a_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :user_b_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :matched_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec
    end

    create unique_index(:matches, [:user_a_id, :user_b_id])
    create constraint(:matches, :matches_ordered, check: "user_a_id < user_b_id")

    create table(:blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :blocker_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :blocked_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :reason, :string
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:blocks, [:blocker_id, :blocked_id])
    create index(:blocks, [:blocked_id])

    create table(:reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :reporter_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :subject_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :message_id, :binary_id
      add :reason, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "open"
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reports, [:subject_id])
    create index(:reports, [:status])
  end
end
