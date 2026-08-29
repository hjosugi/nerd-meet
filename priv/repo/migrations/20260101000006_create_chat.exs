defmodule NerdMeet.Repo.Migrations.CreateChat do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :match_id, references(:matches, type: :binary_id, on_delete: :delete_all), null: false
      add :last_message_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversations, [:match_id])

    # One data key per conversation, stored wrapped under the master key.
    # Deleting this row is the whole of crypto-shredding: the messages stay on
    # disk as ciphertext that nothing can open, including us.
    create table(:conversation_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :wrapped_key, :binary, null: false
      add :wrap_iv, :binary, null: false
      add :wrap_tag, :binary, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:conversation_keys, [:conversation_id])

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id, references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # AES-256-GCM. The plaintext is never written anywhere.
      add :ciphertext, :binary, null: false
      add :iv, :binary, null: false
      add :tag, :binary, null: false

      # A keyed, one-way shingle digest of the normalised text. It lets stage 2
      # measure how templated a sender is without anything being able to read
      # the message back.
      add :fingerprint, :binary

      add :moderation_state, :string, null: false, default: "delivered"
      add :moderation_reason, :string

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:messages, [:conversation_id, :inserted_at])
    create index(:messages, [:sender_id, :inserted_at])
    create index(:messages, [:moderation_state])
  end
end
