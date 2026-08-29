defmodule NerdMeet.Members.SavedQuery do
  @moduledoc """
  A search someone has saved, and may publish on their profile.

  Publishing a query is this product's answer to the "about what I'm looking
  for" paragraph. A condition is falsifiable in a way a paragraph is not: you
  can check whether you satisfy it, and the system can check whether the two of
  you satisfy each other's.

  The stored `filter` is structured. Raw SQL from a user is never executed; the
  SQL shown on a profile is *rendered* from this map for people to read.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Members.Search

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "saved_queries" do
    field :name, :string
    field :description, :string
    field :filter, :map, default: %{}
    field :published, :boolean, default: false

    belongs_to :user, NerdMeet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(query, attrs) do
    query
    |> cast(attrs, [:user_id, :name, :description, :filter, :published])
    |> validate_required([:user_id, :name, :filter])
    |> validate_length(:name, min: 1, max: 60)
    |> validate_filter()
  end

  defp validate_filter(changeset) do
    case get_field(changeset, :filter) do
      filter when is_map(filter) ->
        case Search.validate(filter) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, :filter, message)
        end

      _other ->
        add_error(changeset, :filter, "must be a map")
    end
  end
end
