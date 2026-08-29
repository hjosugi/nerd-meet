import Config

# Print only warnings and errors during test
config :logger, level: :warning

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :nerd_meet, NerdMeet.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "nerd_meet_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# A fixed master key keeps ciphertext reproducible across a test run.
config :nerd_meet, NerdMeet.Vault, master_key: Base.decode64!("bmVyZC1tZWV0LXRlc3QtbWFzdGVyLWtleS0zMmJ5dGU=")

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :nerd_meet, NerdMeetWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4/SdklexYu085Hu0BLdzZqONni1qPgEm4d23dsLYChng4BmV6eW1Iax4nZOtF/zd",
  server: false

# Run Oban jobs inline-free: tests enqueue and assert, or drain explicitly.
config :nerd_meet, Oban, testing: :manual

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
