defmodule NerdMeet.Repo.Migrations.CreateCredentialsAndAuthEvents do
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :credential_id, :binary, null: false
      # DER-encoded SubjectPublicKeyInfo as returned by the authenticator.
      add :public_key, :binary, null: false
      # COSE algorithm identifier: -7 is ES256, -8 is EdDSA.
      add :cose_alg, :integer, null: false

      # A counter that only ever moves forward. If it goes backwards the
      # authenticator has been cloned.
      add :sign_count, :integer, null: false, default: 0

      add :aaguid, :binary
      add :nickname, :string
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_reason, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:credentials, [:credential_id])
    create index(:credentials, [:user_id])

    create table(:auth_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :kind, :string, null: false
      add :country, :string
      add :latitude, :float
      add :longitude, :float

      add :risk_score, :integer, null: false, default: 0
      add :decision, :string, null: false
      add :reasons, :map, null: false, default: %{}

      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:auth_events, [:user_id, :occurred_at])
    create index(:auth_events, [:decision])
  end
end
