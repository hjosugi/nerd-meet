defmodule NerdMeet.Publishing.Snapshot do
  @moduledoc "Metadata for one published static export of the directory."
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "snapshots" do
    field :slug, :string
    field :generated_at, :utc_datetime_usec
    field :record_count, :integer, default: 0
    field :suppressed_count, :integer, default: 0
    field :k, :integer
    field :byte_size, :integer, default: 0
    field :checksum, :string
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :slug,
      :generated_at,
      :record_count,
      :suppressed_count,
      :k,
      :byte_size,
      :checksum
    ])
    |> validate_required([:slug, :generated_at, :k, :checksum])
    |> unique_constraint(:slug)
  end
end
