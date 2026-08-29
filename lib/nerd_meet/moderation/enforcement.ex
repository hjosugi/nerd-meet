defmodule NerdMeet.Moderation.Enforcement do
  @moduledoc """
  A restriction placed on an account.

  `shadow_limit` removes an account from search results while leaving it
  otherwise functional. The point is not deception for its own sake: an
  operator who is told they are banned registers again within the hour, while
  one who thinks the product is simply not working for them takes far longer.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(shadow_limit send_limit suspension)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "enforcements" do
    field :kind, :string
    field :reason, :string
    field :expires_at, :utc_datetime_usec
    field :lifted_at, :utc_datetime_usec

    belongs_to :user, NerdMeet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(enforcement, attrs) do
    enforcement
    |> cast(attrs, [:user_id, :kind, :reason, :expires_at, :lifted_at])
    |> validate_required([:user_id, :kind])
    |> validate_inclusion(:kind, @kinds)
  end

  def kinds, do: @kinds
end
