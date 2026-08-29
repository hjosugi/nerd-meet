defmodule NerdMeet.Vault do
  @moduledoc """
  AES-256-GCM with one data key per conversation.

  A single application-wide key would be simpler, and would also mean that
  "delete my messages" could only ever be a `DELETE` statement whose effect
  nobody outside the operator can verify. Per-conversation keys turn deletion
  into something structural: destroy the wrapped key and the ciphertext is
  unreadable to everyone, us included. That is the whole of
  `NerdMeet.Privacy.Deletion`.

  The master key wraps data keys and nothing else. It lives in the environment,
  never in the database, so a dump of the database is inert on its own.
  """

  alias NerdMeet.Moderation.Text

  @aad "nerd-meet/v1"
  @cipher :aes_256_gcm
  @iv_bytes 12
  @tag_bytes 16
  @key_bytes 32

  @type sealed :: %{ciphertext: binary(), iv: binary(), tag: binary()}

  @doc "A fresh 256-bit data key."
  @spec generate_key() :: binary()
  def generate_key, do: :crypto.strong_rand_bytes(@key_bytes)

  @doc """
  Encrypts `plaintext` under `key`.

  The IV is random per call, which is what makes it safe to reuse a data key
  across every message in a conversation.
  """
  @spec seal(binary(), binary()) :: sealed()
  def seal(key, plaintext) when byte_size(key) == @key_bytes and is_binary(plaintext) do
    iv = :crypto.strong_rand_bytes(@iv_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(@cipher, key, iv, plaintext, @aad, @tag_bytes, true)

    %{ciphertext: ciphertext, iv: iv, tag: tag}
  end

  @doc """
  Decrypts a sealed payload, returning `:error` on any tampering.
  """
  @spec open(binary(), sealed()) :: {:ok, binary()} | :error
  def open(key, %{ciphertext: ciphertext, iv: iv, tag: tag}) when byte_size(key) == @key_bytes do
    case :crypto.crypto_one_time_aead(@cipher, key, iv, ciphertext, @aad, tag, false) do
      :error -> :error
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
    end
  end

  @doc "Wraps a data key under the master key."
  @spec wrap(binary()) :: sealed()
  def wrap(data_key), do: seal(master_key(), data_key)

  @doc "Unwraps a data key. Fails closed if the master key has changed."
  @spec unwrap(sealed()) :: {:ok, binary()} | :error
  def unwrap(sealed), do: open(master_key(), sealed)

  @doc """
  A keyed, one-way digest of a message that supports similarity comparison.

  Stage 2 needs to know whether a sender is pasting the same text at fifty
  people. It does not need to know what the text says. This is a SimHash over
  keyed character shingles: two near-identical messages produce digests a small
  Hamming distance apart, and the digest cannot be turned back into text.
  """
  @spec fingerprint(binary()) :: binary()
  def fingerprint(text) when is_binary(text) do
    key = derive("fingerprint")

    text
    |> Text.normalize()
    |> Text.squash()
    |> shingles(3)
    |> case do
      [] -> <<0::64>>
      list -> simhash(list, key)
    end
  end

  @doc """
  Hamming distance between two fingerprints, 0 (identical) to 64 (unrelated).
  """
  @spec similarity(binary(), binary()) :: non_neg_integer()
  def similarity(<<a::64>>, <<b::64>>) do
    a
    |> Bitwise.bxor(b)
    |> Integer.digits(2)
    |> Enum.sum()
  end

  @doc """
  The configured master key.

  Raises rather than falling back to a default. A silent default here would
  mean shipping a system whose encryption is decorative.
  """
  @spec master_key() :: binary()
  def master_key do
    case Application.get_env(:nerd_meet, __MODULE__, [])[:master_key] do
      <<key::binary-size(@key_bytes)>> ->
        key

      _other ->
        raise """
        NerdMeet.Vault master key is missing or not 32 bytes.
        Set VAULT_MASTER_KEY (base64 of 32 random bytes) in the environment.
        """
    end
  end

  defp derive(label) do
    :crypto.mac(:hmac, :sha256, master_key(), label)
  end

  defp shingles(text, size) do
    graphemes = String.graphemes(text)

    if length(graphemes) <= size do
      if graphemes == [], do: [], else: [Enum.join(graphemes)]
    else
      graphemes
      |> Enum.chunk_every(size, 1, :discard)
      |> Enum.map(&Enum.join/1)
    end
  end

  defp simhash(shingles, key) do
    counters =
      Enum.reduce(shingles, List.duplicate(0, 64), fn shingle, acc ->
        <<bits::64, _rest::binary>> = :crypto.mac(:hmac, :sha256, key, shingle)

        acc
        |> Enum.with_index()
        |> Enum.map(fn {count, index} ->
          if Bitwise.band(Bitwise.bsr(bits, index), 1) == 1, do: count + 1, else: count - 1
        end)
      end)

    value =
      counters
      |> Enum.with_index()
      |> Enum.reduce(0, fn {count, index}, acc ->
        if count > 0, do: Bitwise.bor(acc, Bitwise.bsl(1, index)), else: acc
      end)

    <<value::64>>
  end
end
