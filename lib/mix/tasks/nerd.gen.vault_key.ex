defmodule Mix.Tasks.Nerd.Gen.VaultKey do
  @shortdoc "Generates a base64 master key for VAULT_MASTER_KEY"
  @moduledoc """
  Prints 32 random bytes, base64 encoded, for use as `VAULT_MASTER_KEY`.

      $ mix nerd.gen.vault_key

  This key wraps every per-conversation data key. Losing it makes every stored
  message permanently unreadable — which is exactly what crypto-shredding is
  for, and a very bad accident.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64() |> Mix.shell().info()
  end
end
