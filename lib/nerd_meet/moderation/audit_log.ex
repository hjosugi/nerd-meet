defmodule NerdMeet.Moderation.AuditLog do
  @moduledoc """
  An append-only record of privileged access.

  Any system where staff can read flagged messages has to answer "how would
  anyone know if that access were abused?" This table is the answer, and it is
  in an open-source repository so the answer can be checked rather than
  believed.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_logs" do
    field :action, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :reason, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    belongs_to :actor, NerdMeet.Accounts.User
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:actor_id, :action, :subject_type, :subject_id, :reason, :metadata])
    |> validate_required([:action, :subject_type, :reason])
    |> validate_length(:reason, min: 3, message: "監査ログには実質的な理由が必要です")
    |> put_change(:occurred_at, DateTime.utc_now())
  end
end
