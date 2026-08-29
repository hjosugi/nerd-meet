defmodule NerdMeetWeb.Router do
  use NerdMeetWeb, :router

  alias NerdMeetWeb.Plugs.CurrentUser

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {NerdMeetWeb.Layouts, :root}
    plug :protect_from_forgery
    # Everything this application serves is its own: no third-party script,
    # font or analytics endpoint is loaded, so the policy says exactly that
    # rather than enumerating exceptions.
    plug :put_secure_browser_headers,
         %{
           "content-security-policy" =>
             "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
         }

    plug CurrentUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", NerdMeetWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/directory", DirectoryController, :index

    live_session :member, on_mount: {CurrentUser, :current_user} do
      live "/matches", MatchLive
      live "/chat/:user_id", ChatLive
    end
  end

  scope "/", NerdMeetWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  # Development only. The browser half of the passkey ceremony is not built
  # yet, so there has to be some way to hold a session while the rest of the
  # product is worked on. It is compiled out of any build where :dev_routes is
  # false, which includes every production release.
  if Application.compile_env(:nerd_meet, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev", NerdMeetWeb do
      pipe_through :browser

      get "/session/:handle", DevSessionController, :create
      delete "/session", DevSessionController, :delete
    end

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: NerdMeetWeb.Telemetry
    end
  end
end
