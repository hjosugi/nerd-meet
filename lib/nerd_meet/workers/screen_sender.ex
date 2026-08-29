defmodule NerdMeet.Workers.ScreenSender do
  @moduledoc """
  Runs stages 2 and 3 for the sender of a message.

  Queued after the message has already been delivered. Moderation that a member
  can feel is moderation they will route around.
  """
  use Oban.Worker, queue: :moderation, max_attempts: 3, unique: [period: 60, keys: [:user_id]]

  alias NerdMeet.Moderation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    Moderation.review_account(user_id, message_id: args["message_id"])
    :ok
  end
end
