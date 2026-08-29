defmodule NerdMeet.Social.Like do
  @moduledoc "A one-way expression of interest. Two of them make a match."
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "likes" do
    field :inserted_at, :utc_datetime_usec

    belongs_to :from_user, User
    belongs_to :to_user, User
  end

  @doc false
  def changeset(like, attrs) do
    like
    |> cast(attrs, [:from_user_id, :to_user_id, :inserted_at])
    |> validate_required([:from_user_id, :to_user_id])
    |> put_timestamp()
    |> check_constraint(:from_user_id, name: :likes_not_self, message: "自分にはいいねできません")
    |> unique_constraint([:from_user_id, :to_user_id])
  end

  defp put_timestamp(changeset) do
    case get_field(changeset, :inserted_at) do
      nil -> put_change(changeset, :inserted_at, DateTime.utc_now())
      _set -> changeset
    end
  end
end
