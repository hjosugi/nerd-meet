defmodule NerdMeet.Accounts.IdentityProvider do
  @moduledoc """
  Adult verification against a government-issued certificate.

  In Japan this is JPKI: the card's signature certificate carries a serial, a
  date of birth and an address, and verifying it proves an adult human is
  behind the account without the service ever holding the card.

  Two things this behaviour is careful about:

    * It returns **derived** attributes only. The birth year, not the birth
      date; the prefecture, not the address; a hash of the serial, not the
      serial. What is never received cannot leak.
    * It is an external call, so it is a behaviour with a mock, and callers are
      expected to invoke it *before* opening a transaction. Holding a database
      connection open across a network round trip to a government endpoint is
      how a verification outage becomes a total outage.
  """

  @type result :: %{
          serial_hash: binary(),
          birth_year: pos_integer(),
          prefecture: binary()
        }

  @callback verify(payload :: map()) :: {:ok, result()} | {:error, atom()}

  @doc "The configured provider, defaulting to the mock."
  @spec impl() :: module()
  def impl do
    Application.get_env(:nerd_meet, :identity_provider, NerdMeet.Accounts.IdentityProvider.Mock)
  end

  @spec verify(map()) :: {:ok, result()} | {:error, atom()}
  def verify(payload), do: impl().verify(payload)

  @doc """
  Hashes a certificate serial for storage.

  Stored so that a suspended person cannot register again, and hashed so that
  the column cannot be joined against anything.
  """
  @spec hash_serial(binary()) :: binary()
  def hash_serial(serial), do: :crypto.hash(:sha256, "jpki-serial:" <> serial)
end

defmodule NerdMeet.Accounts.IdentityProvider.Mock do
  @moduledoc """
  A provider for development and tests that trusts what it is given.

  Never configure this in production; `config/runtime.exs` is where the real
  one is wired.
  """
  @behaviour NerdMeet.Accounts.IdentityProvider

  alias NerdMeet.Accounts.IdentityProvider

  @impl true
  def verify(%{"serial" => serial, "birth_year" => birth_year} = payload) do
    if birth_year <= adult_cutoff() do
      {:ok,
       %{
         serial_hash: IdentityProvider.hash_serial(serial),
         birth_year: birth_year,
         prefecture: Map.get(payload, "prefecture", "東京都")
       }}
    else
      {:error, :under_age}
    end
  end

  def verify(_payload), do: {:error, :invalid_payload}

  defp adult_cutoff, do: Date.utc_today().year - 18
end
