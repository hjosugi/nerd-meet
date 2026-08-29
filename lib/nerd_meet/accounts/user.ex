defmodule NerdMeet.Accounts.User do
  @moduledoc """
  An account. Deliberately thin: everything a person writes about themselves
  lives on `NerdMeet.Members.Profile`, so that suspending or deleting an
  identity does not have to reason about profile content.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending active suspended deleted)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :handle, :string
    field :status, :string, default: "pending"
    field :verified_at, :utc_datetime_usec
    field :identity_serial_hash, :binary
    field :birth_year, :integer
    field :prefecture, :string
    field :last_country, :string
    field :last_latitude, :float
    field :last_longitude, :float
    field :last_seen_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    has_one :profile, NerdMeet.Members.Profile
    has_many :credentials, NerdMeet.Accounts.Credential

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:handle, :birth_year, :prefecture, :identity_serial_hash])
    |> update_change(:handle, &String.downcase/1)
    |> validate_required([:handle])
    |> validate_length(:handle, min: 3, max: 32)
    |> validate_format(:handle, ~r/\A[a-z0-9_\-]+\z/, message: "は英小文字・数字・アンダースコア・ハイフンのみ使えます")
    |> unique_constraint(:handle)
    |> unique_constraint(:identity_serial_hash,
      message: "この本人確認書類は既に登録されています"
    )
  end

  @doc false
  def verification_changeset(user, attrs) do
    user
    |> cast(attrs, [:verified_at, :birth_year, :prefecture, :identity_serial_hash, :status])
    |> validate_required([:verified_at, :birth_year])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:identity_serial_hash)
  end

  @doc false
  def status_changeset(user, status) when status in @statuses do
    change(user, status: status)
  end

  @doc false
  def location_changeset(user, attrs) do
    cast(user, attrs, [:last_country, :last_latitude, :last_longitude, :last_seen_at])
  end

  @doc "Statuses an account may hold."
  def statuses, do: @statuses
end
