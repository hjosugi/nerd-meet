defmodule NerdMeet.VaultTest do
  use ExUnit.Case, async: true

  alias NerdMeet.Vault

  describe "seal and open" do
    test "a sealed message round-trips" do
      key = Vault.generate_key()
      sealed = Vault.seal(key, "PostgreSQLの話をしましょう")

      assert {:ok, "PostgreSQLの話をしましょう"} = Vault.open(key, sealed)
    end

    test "ciphertext contains no trace of the plaintext" do
      key = Vault.generate_key()
      sealed = Vault.seal(key, "秘密のメッセージ")

      refute String.contains?(sealed.ciphertext, "秘密")
      refute sealed.ciphertext == "秘密のメッセージ"
    end

    test "the same plaintext seals differently every time" do
      key = Vault.generate_key()

      assert Vault.seal(key, "同じ本文").ciphertext != Vault.seal(key, "同じ本文").ciphertext
    end

    test "a tampered tag fails instead of returning garbage" do
      key = Vault.generate_key()
      sealed = Vault.seal(key, "改ざん検知")

      assert :error = Vault.open(key, %{sealed | tag: :crypto.strong_rand_bytes(16)})
    end

    test "the wrong key cannot open it" do
      sealed = Vault.seal(Vault.generate_key(), "他人のメッセージ")

      assert :error = Vault.open(Vault.generate_key(), sealed)
    end
  end

  describe "wrap and unwrap" do
    test "a data key round-trips through the master key" do
      key = Vault.generate_key()

      assert {:ok, ^key} = key |> Vault.wrap() |> Vault.unwrap()
    end
  end

  describe "fingerprint" do
    test "identical text produces identical digests" do
      assert Vault.fingerprint("はじめまして") == Vault.fingerprint("はじめまして")
    end

    test "a near-duplicate stays close" do
      a = Vault.fingerprint("はじめまして、Elixirを書いています。よかったら話しませんか")
      b = Vault.fingerprint("はじめまして、Elixirを書いています。よければ話しませんか")

      assert Vault.similarity(a, b) <= 16
    end

    test "unrelated text is far apart" do
      a = Vault.fingerprint("はじめまして、Elixirを書いています。よかったら話しませんか")
      b = Vault.fingerprint("週末は山に登っていました。写真を撮るのが好きです")

      assert Vault.similarity(a, b) > 16
    end

    test "the digest does not carry the text" do
      digest = Vault.fingerprint("連絡先はこちらです")

      assert byte_size(digest) == 8
      refute String.contains?(digest, "連絡")
    end
  end
end
