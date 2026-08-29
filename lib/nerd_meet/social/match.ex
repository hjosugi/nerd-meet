defmodule NerdMeet.Social.Match do
  @moduledoc """
  A mutual like. Chat exists only for a pair that has one, which is the single
  most effective structural defence against unsolicited contact.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "matches" do
    field :matched_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    belongs_to :user_a, User
    belongs_to :user_b, User
    has_one :conversation, NerdMeet.Chat.Conversation
  end

  @doc false
  def changeset(match, attrs) do
    match
    |> cast(attrs, [:user_a_id, :user_b_id, :matched_at, :closed_at])
    |> validate_required([:user_a_id, :user_b_id, :matched_at])
    |> unique_constraint([:user_a_id, :user_b_id])
    |> check_constraint(:user_a_id, name: :matches_ordered)
  end

  @doc """
  Orders a pair so that a match has one canonical row regardless of who liked
  first.
  """
  @spec order(binary(), binary()) :: {binary(), binary()}
  def order(a, b) when a < b, do: {a, b}
  def order(a, b), do: {b, a}
end
