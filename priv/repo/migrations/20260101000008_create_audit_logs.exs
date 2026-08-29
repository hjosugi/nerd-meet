defmodule NerdMeet.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    # Every read of message plaintext by a human writes a row here. Without it,
    # "staff can read flagged messages" quietly becomes "staff can read
    # anything". The table is append-only by convention and by revoked UPDATE
    # and DELETE grants in production.
    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :binary_id
      add :reason, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:audit_logs, [:actor_id, :occurred_at])
    create index(:audit_logs, [:subject_type, :subject_id])
  end
end
