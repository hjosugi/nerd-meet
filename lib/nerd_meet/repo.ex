defmodule NerdMeet.Repo do
  use Ecto.Repo,
    otp_app: :nerd_meet,
    adapter: Ecto.Adapters.Postgres
end
