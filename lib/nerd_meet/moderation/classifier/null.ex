defmodule NerdMeet.Moderation.Classifier.Null do
  @moduledoc """
  The default stage 3: decides nothing and leaves the case for a human.

  This is not a stub standing in for the real thing. It is the correct default
  for a deployment that has not chosen a model provider, and it fails in the
  safe direction: the message stays in the review queue rather than being
  cleared by something that never looked at it.
  """
  @behaviour NerdMeet.Moderation.Classifier

  @impl true
  def classify(_body, _context) do
    {:ok, %{verdict: "suspect", confidence: 0.0, reasons: ["no_classifier_configured"]}}
  end
end
