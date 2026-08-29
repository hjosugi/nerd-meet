defmodule NerdMeet.Accounts.AuthEvent do
  @moduledoc """
  One authentication decision, kept so that the next one has something to
  compare against. The risk engine is only as good as this history.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auth_events" do
    field :kind, :string
    field :country, :string
    field :latitude, :float
    field :longitude, :float
    field :risk_score, :integer, default: 0
    field :decision, :string
    field :reasons, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    belongs_to :user, NerdMeet.Accounts.User
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :user_id,
      :kind,
      :country,
      :latitude,
      :longitude,
      :risk_score,
      :decision,
      :reasons,
      :occurred_at
    ])
    |> validate_required([:kind, :decision, :occurred_at])
    |> validate_inclusion(:decision, ~w(allow step_up deny revoke_all))
  end
end
