defmodule NerdMeet.Members.Profile do
  @moduledoc """
  What someone chooses to say about themselves, in fields rather than prose.

  There is no photo column and there will not be one. The product is a search
  over structured facts; a face grid is a different product with a different
  failure mode.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @visibilities ~w(directory matches_only hidden)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "profiles" do
    field :display_name, :string
    field :headline, :string
    field :bio, :string
    field :birth_year, :integer
    field :prefecture, :string
    field :region, :string
    field :years_experience, :integer
    field :remote_ok, :boolean, default: false
    field :languages, {:array, :string}, default: []
    field :skills, {:array, :string}, default: []
    field :tools, {:array, :string}, default: []
    field :github_handle, :string
    field :blog_url, :string
    field :visibility, :string, default: "directory"

    belongs_to :user, NerdMeet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :user_id,
      :display_name,
      :headline,
      :bio,
      :birth_year,
      :prefecture,
      :years_experience,
      :remote_ok,
      :languages,
      :skills,
      :tools,
      :github_handle,
      :blog_url,
      :visibility
    ])
    |> validate_required([:user_id, :display_name])
    |> validate_length(:display_name, min: 1, max: 40)
    |> validate_length(:headline, max: 120)
    |> validate_length(:bio, max: 2000)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_number(:years_experience, greater_than_or_equal_to: 0, less_than: 60)
    |> validate_number(:birth_year, greater_than: 1930, less_than: 2012)
    |> validate_subset(:languages, NerdMeet.Members.known_languages())
    |> put_region()
    |> unique_constraint(:user_id)
  end

  def visibilities, do: @visibilities

  # The region is derived, never entered. It is the first rung of the
  # anonymity ladder: when a prefecture bucket is too small to publish, the
  # region bucket usually is not.
  defp put_region(changeset) do
    case get_field(changeset, :prefecture) do
      nil -> changeset
      prefecture -> put_change(changeset, :region, NerdMeet.Members.region_for(prefecture))
    end
  end
end
