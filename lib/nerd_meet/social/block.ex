defmodule NerdMeet.Social.Block do
  @moduledoc "A block is absolute: no messages, no directory visibility, either way."
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blocks" do
    field :reason, :string
    field :inserted_at, :utc_datetime_usec

    belongs_to :blocker, User
    belongs_to :blocked, User
  end

  @doc false
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id, :reason])
    |> validate_required([:blocker_id, :blocked_id])
    |> put_change(:inserted_at, DateTime.utc_now())
    |> unique_constraint([:blocker_id, :blocked_id])
  end
end
