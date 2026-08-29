defmodule NerdMeet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      NerdMeetWeb.Telemetry,
      NerdMeet.Repo,
      {DNSCluster, query: Application.get_env(:nerd_meet, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:nerd_meet, Oban)},
      {Phoenix.PubSub, name: NerdMeet.PubSub},
      # Start a worker by calling: NerdMeet.Worker.start_link(arg)
      # {NerdMeet.Worker, arg},
      # Start to serve requests, typically the last entry
      NerdMeetWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NerdMeet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NerdMeetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
