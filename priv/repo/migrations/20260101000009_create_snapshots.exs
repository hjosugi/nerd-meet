defmodule NerdMeet.Repo.Migrations.CreateSnapshots do
  use Ecto.Migration

  def change do
    create table(:snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :generated_at, :utc_datetime_usec, null: false
      add :record_count, :integer, null: false, default: 0
      add :suppressed_count, :integer, null: false, default: 0
      add :k, :integer, null: false
      add :byte_size, :integer, null: false, default: 0
      add :checksum, :string, null: false
    end

    create unique_index(:snapshots, [:slug])
  end
end
