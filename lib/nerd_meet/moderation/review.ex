defmodule NerdMeet.Moderation.Review do
  @moduledoc "One verdict from one stage of the cascade."
  use Ecto.Schema

  import Ecto.Changeset

  alias NerdMeet.Accounts.User

  @stages ~w(rules signals classifier human)
  @verdicts ~w(clear suspect violation)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "moderation_reviews" do
    field :stage, :string
    field :score, :integer, default: 0
    field :verdict, :string
    field :reasons, {:array, :string}, default: []
    field :resolved_at, :utc_datetime_usec
    field :resolution, :string

    belongs_to :message, NerdMeet.Chat.Message
    belongs_to :subject, User
    belongs_to :reviewer, User

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :message_id,
      :subject_id,
      :stage,
      :score,
      :verdict,
      :reasons,
      :reviewer_id,
      :resolved_at,
      :resolution
    ])
    |> validate_required([:subject_id, :stage, :verdict])
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:verdict, @verdicts)
  end

  def stages, do: @stages
  def verdicts, do: @verdicts
end
