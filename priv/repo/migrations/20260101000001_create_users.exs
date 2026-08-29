defmodule NerdMeet.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :status, :string, null: false, default: "pending"

      # Set once identity verification succeeds. Until then the account cannot
      # appear in the directory or send a message.
      add :verified_at, :utc_datetime_usec

      # SHA-256 of the identity certificate serial. Never the serial itself, so
      # a leak of this table cannot be joined back to a certificate registry.
      # Unique so a suspended person cannot simply register again.
      add :identity_serial_hash, :binary

      add :birth_year, :integer
      add :prefecture, :string

      # Last observed sign-in location, used by the risk engine.
      add :last_country, :string
      add :last_latitude, :float
      add :last_longitude, :float
      add :last_seen_at, :utc_datetime_usec

      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:handle])
    create unique_index(:users, [:identity_serial_hash])
    create index(:users, [:status])
  end
end
