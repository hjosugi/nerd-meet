defmodule NerdMeet.Moderation.Classifier do
  @moduledoc """
  Stage 3: the expensive judgement, reached by very little traffic.

  Stages 1 and 2 exist so that this one runs on a percent or two of messages
  rather than all of them. That ratio, not the model, is what makes
  model-backed moderation affordable, so the threshold that gates this stage is
  configuration rather than a constant.

  The shipped implementation makes no external call. Sending member messages to
  a third party is a decision an operator has to make deliberately and disclose
  in a privacy policy, so it cannot be the default in a repository anyone can
  deploy.
  """

  @type verdict :: %{verdict: binary(), confidence: float(), reasons: [binary()]}

  @callback classify(body :: binary(), context :: map()) :: {:ok, verdict()} | {:error, term()}

  @spec impl() :: module()
  def impl do
    Application.get_env(:nerd_meet, :moderation, [])[:classifier] ||
      NerdMeet.Moderation.Classifier.Null
  end

  @spec classify(binary(), map()) :: {:ok, verdict()} | {:error, term()}
  def classify(body, context \\ %{}), do: impl().classify(body, context)
end
