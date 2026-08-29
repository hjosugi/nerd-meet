defmodule NerdMeet.Social.Report do
  @moduledoc "A report from one member about another. Feeds stage 2 as a signal."
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Accounts.User

  @reasons ~w(solicitation harassment impersonation spam minor other)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "reports" do
    field :message_id, Ecto.UUID
    field :reason, :string
    field :body, :string
    field :status, :string, default: "open"
    field :inserted_at, :utc_datetime_usec

    belongs_to :reporter, User
    belongs_to :subject, User
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:reporter_id, :subject_id, :message_id, :reason, :body])
    |> validate_required([:subject_id, :reason])
    |> validate_inclusion(:reason, @reasons)
    |> put_change(:inserted_at, DateTime.utc_now())
  end

  def reasons, do: @reasons
end
