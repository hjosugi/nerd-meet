# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  nerd_meet: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configures the endpoint
config :nerd_meet, NerdMeetWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NerdMeetWeb.ErrorHTML, json: NerdMeetWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NerdMeet.PubSub,
  live_view: [signing_salt: "2dD+C5JH"]

# Background jobs. Moderation stages 2 and 3 run here so that sending a
# message never waits on anything but the cheap stage 1 check.
config :nerd_meet, Oban,
  repo: NerdMeet.Repo,
  queues: [moderation: 10, snapshots: 1, deletion: 3],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)}
  ]

# Stage 3 of the moderation cascade. The default classifier makes no external
# call at all; point this at an adapter to enable model-backed review.
config :nerd_meet, :moderation,
  classifier: NerdMeet.Moderation.Classifier.Null,
  # Behavioural score at or above which a message is queued for human review.
  review_threshold: 60

# k-anonymity floor for every aggregate the directory exposes.
config :nerd_meet, :privacy,
  k: 5,
  # Bands are widened in this order until the k floor is met.
  band_ladder: [:fine, :medium, :coarse]

config :nerd_meet,
  ecto_repos: [NerdMeet.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  nerd_meet: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
