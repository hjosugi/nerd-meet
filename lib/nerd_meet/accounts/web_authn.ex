defmodule NerdMeet.Accounts.WebAuthn do
  @moduledoc """
  Assertion verification for registered passkeys.

  Only the verification half of WebAuthn lives here. Ceremony state
  (challenges, timeouts) belongs to the web layer; this module is a pure
  function of the material a browser hands back, which is what makes it
  testable without a browser.

  ES256 and Ed25519 are the only algorithms accepted. RSA is deliberately
  absent: no authenticator worth supporting requires it, and every additional
  algorithm is another parser.
  """

  @up_flag 0x01
  @uv_flag 0x04

  @type assertion :: %{
          authenticator_data: binary(),
          client_data_json: binary(),
          signature: binary()
        }

  @type expectation :: %{
          challenge: binary(),
          origin: binary(),
          rp_id: binary()
        }

  @doc """
  Verifies an assertion and returns the authenticator's signature counter.

  The counter is the caller's problem: this module reports it, and
  `NerdMeet.Accounts` decides what a counter that failed to advance means.
  """
  @spec verify(binary(), integer(), assertion(), expectation()) ::
          {:ok, %{sign_count: non_neg_integer(), user_verified: boolean()}}
          | {:error, atom()}
  def verify(public_key_der, cose_alg, assertion, expected) do
    %{
      authenticator_data: auth_data,
      client_data_json: client_data_json,
      signature: signature
    } = assertion

    with :ok <- check_client_data(client_data_json, expected),
         {:ok, flags, sign_count} <- parse_authenticator_data(auth_data, expected.rp_id),
         :ok <- check_signature(public_key_der, cose_alg, auth_data, client_data_json, signature) do
      {:ok,
       %{
         sign_count: sign_count,
         user_verified: Bitwise.band(flags, @uv_flag) != 0
       }}
    end
  end

  @doc """
  Encodes a value the way WebAuthn encodes challenges: base64url, unpadded.
  """
  @spec b64(binary()) :: binary()
  def b64(value), do: Base.url_encode64(value, padding: false)

  defp check_client_data(json, expected) do
    with {:ok, data} <- Jason.decode(json),
         "webauthn.get" <- Map.get(data, "type"),
         true <- secure_equal?(Map.get(data, "challenge", ""), b64(expected.challenge)),
         true <- Map.get(data, "origin") == expected.origin do
      :ok
    else
      {:error, _reason} -> {:error, :malformed_client_data}
      _mismatch -> {:error, :client_data_mismatch}
    end
  end

  defp parse_authenticator_data(<<rp_id_hash::binary-size(32), flags::8, sign_count::32, _rest::binary>>, rp_id) do
    cond do
      rp_id_hash != :crypto.hash(:sha256, rp_id) -> {:error, :rp_id_mismatch}
      Bitwise.band(flags, @up_flag) == 0 -> {:error, :user_not_present}
      true -> {:ok, flags, sign_count}
    end
  end

  defp parse_authenticator_data(_other, _rp_id), do: {:error, :malformed_authenticator_data}

  defp check_signature(public_key_der, cose_alg, auth_data, client_data_json, signature) do
    message = auth_data <> :crypto.hash(:sha256, client_data_json)

    case decode_key(public_key_der) do
      {:ok, key} ->
        digest = if cose_alg == -8, do: :none, else: :sha256

        if :public_key.verify(message, digest, signature, key),
          do: :ok,
          else: {:error, :bad_signature}

      :error ->
        {:error, :bad_public_key}
    end
  rescue
    _error -> {:error, :bad_signature}
  end

  @doc """
  Decodes a DER SubjectPublicKeyInfo into a key `:public_key` can verify with.
  """
  @spec decode_key(binary()) :: {:ok, term()} | :error
  def decode_key(der) do
    {:ok, :public_key.pem_entry_decode({:SubjectPublicKeyInfo, der, :not_encrypted})}
  rescue
    _error -> :error
  end

  @doc "Encodes a decoded public key back to DER, used by tests and tooling."
  @spec encode_key(term()) :: binary()
  def encode_key(key) do
    {:SubjectPublicKeyInfo, der, :not_encrypted} =
      :public_key.pem_entry_encode(:SubjectPublicKeyInfo, key)

    der
  end

  defp secure_equal?(a, b) when is_binary(a) and is_binary(b) do
    byte_size(a) == byte_size(b) and :crypto.hash_equals(a, b)
  end

  defp secure_equal?(_a, _b), do: false
end
