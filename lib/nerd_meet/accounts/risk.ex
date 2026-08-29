defmodule NerdMeet.Accounts.Risk do
  @moduledoc """
  Scores a sign-in attempt so that friction can be spent where it buys
  something.

  The usual failure of "strong authentication" is that it taxes everybody
  equally: a second factor at every sign-in from the same phone in the same
  city, which people learn to click through without reading. Scoring inverts
  that. A sign-in that looks like the last twenty costs nothing, and the budget
  saved is spent on the one that does not.

  Signals, and why each is here:

    * a country that has never been seen before, which is cheap to observe and
      hard to fake accidentally
    * travel between two sign-ins that no aircraft could have made
    * an authenticator being used for the first time
    * a signature counter that failed to advance, which is not a risk signal at
      all but proof that key material has been copied out of its device

  The last one is not scored. It ends the session and every other session,
  because there is no threshold at which a cloned authenticator is acceptable.
  """

  alias NerdMeet.Accounts.AuthEvent
  alias NerdMeet.Accounts.User

  # Roughly the ground speed of an airliner. Anything faster is either a VPN or
  # two people holding the same credential; both deserve a second look.
  @impossible_speed_kmh 900
  @minimum_hours 1 / 60
  @step_up_threshold 50

  @type context :: %{
          optional(:country) => binary() | nil,
          optional(:latitude) => float() | nil,
          optional(:longitude) => float() | nil,
          optional(:at) => DateTime.t(),
          optional(:new_credential) => boolean()
        }

  @type assessment :: %{
          score: non_neg_integer(),
          decision: :allow | :step_up,
          reasons: [binary()]
        }

  @doc """
  Scores one attempt against what is known about the account.
  """
  @spec assess(User.t() | map(), context(), AuthEvent.t() | nil) :: assessment()
  def assess(user, context, last_event \\ nil) do
    reasons =
      []
      |> add(country_change(user, context))
      |> add(impossible_travel(user, context, last_event))
      |> add(new_credential(context))

    score = reasons |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> min(100)

    %{
      score: score,
      decision: if(score >= @step_up_threshold, do: :step_up, else: :allow),
      reasons: Enum.map(reasons, &elem(&1, 0))
    }
  end

  @doc "The score at or above which re-authentication is demanded."
  @spec step_up_threshold() :: pos_integer()
  def step_up_threshold, do: @step_up_threshold

  @doc """
  Great-circle distance in kilometres.
  """
  @spec distance_km({float(), float()}, {float(), float()}) :: float()
  def distance_km({lat1, lon1}, {lat2, lon2}) do
    radius = 6371.0
    dlat = deg_to_rad(lat2 - lat1)
    dlon = deg_to_rad(lon2 - lon1)

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(deg_to_rad(lat1)) * :math.cos(deg_to_rad(lat2)) *
          :math.pow(:math.sin(dlon / 2), 2)

    radius * 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
  end

  defp add(reasons, nil), do: reasons
  defp add(reasons, reason), do: [reason | reasons]

  defp country_change(user, context) do
    known = Map.get(user, :last_country)
    seen = Map.get(context, :country)

    if is_binary(known) and is_binary(seen) and known != seen,
      do: {"country_change", 40}
  end

  defp impossible_travel(user, context, last_event) do
    with {:ok, from, from_at} <- last_location(user, last_event),
         {:ok, to, to_at} <- current_location(context) do
      # Two sign-ins can be seconds apart, so the elapsed time is floored at a
      # minute. Without the floor the division blows up on exactly the case the
      # check exists for: the same account appearing in two places at once.
      hours = max(DateTime.diff(to_at, from_at, :second) / 3600, @minimum_hours)
      speed = distance_km(from, to) / hours

      if speed > @impossible_speed_kmh, do: {"impossible_travel", 60}
    else
      _insufficient_data -> nil
    end
  end

  defp new_credential(%{new_credential: true}), do: {"new_authenticator", 20}
  defp new_credential(_context), do: nil

  defp last_location(_user, %AuthEvent{latitude: lat, longitude: lon, occurred_at: at})
       when is_float(lat) and is_float(lon),
       do: {:ok, {lat, lon}, at}

  defp last_location(user, _event) do
    case {Map.get(user, :last_latitude), Map.get(user, :last_longitude), Map.get(user, :last_seen_at)} do
      {lat, lon, at} when is_float(lat) and is_float(lon) and not is_nil(at) ->
        {:ok, {lat, lon}, at}

      _missing ->
        :error
    end
  end

  defp current_location(context) do
    case {Map.get(context, :latitude), Map.get(context, :longitude)} do
      {lat, lon} when is_float(lat) and is_float(lon) ->
        {:ok, {lat, lon}, Map.get(context, :at) || DateTime.utc_now()}

      _missing ->
        :error
    end
  end

  defp deg_to_rad(degrees), do: degrees * :math.pi() / 180.0
end
