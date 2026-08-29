defmodule NerdMeet.Fixtures do
  @moduledoc "Builders for the objects most tests need before they can start."

  alias NerdMeet.Accounts
  alias NerdMeet.Accounts.WebAuthn
  alias NerdMeet.Members
  alias NerdMeet.Social

  @doc "A verified, active member with a directory profile."
  def member(attrs \\ %{}) do
    handle = Map.get(attrs, :handle, "member#{System.unique_integer([:positive])}")

    {:ok, user} =
      Accounts.register(%{
        "handle" => handle,
        "identity" => %{
          "serial" => "serial-#{System.unique_integer([:positive])}",
          "birth_year" => Map.get(attrs, :birth_year, 1990),
          "prefecture" => Map.get(attrs, :prefecture, "東京都")
        }
      })

    {:ok, _profile} =
      Members.upsert_profile(user.id, %{
        display_name: Map.get(attrs, :display_name, handle),
        headline: Map.get(attrs, :headline, "backend engineer"),
        birth_year: Map.get(attrs, :birth_year, 1990),
        prefecture: Map.get(attrs, :prefecture, "東京都"),
        years_experience: Map.get(attrs, :years_experience, 8),
        remote_ok: Map.get(attrs, :remote_ok, true),
        languages: Map.get(attrs, :languages, ["elixir"]),
        skills: Map.get(attrs, :skills, ["postgresql"]),
        tools: Map.get(attrs, :tools, [])
      })

    user
  end

  @doc "Two members who have liked each other."
  def matched_pair do
    a = member()
    b = member()
    {:ok, _first} = Social.like(a.id, b.id)
    {:ok, _second} = Social.like(b.id, a.id)
    {a, b}
  end

  @doc """
  A P-256 key pair plus a registered credential, so assertion verification can
  be exercised without a browser.
  """
  def passkey(user_id, opts \\ []) do
    private = :public_key.generate_key({:namedCurve, :secp256r1})
    # #'ECPrivateKey'{version, privateKey, parameters, publicKey, attributes}.
    # The parameters field already holds the curve as the OID tuple DER
    # encoding expects, so it is reused rather than spelled out again.
    public = {{:ECPoint, elem(private, 4)}, elem(private, 3)}
    der = WebAuthn.encode_key(public)
    credential_id = :crypto.strong_rand_bytes(16)

    {:ok, credential} =
      Accounts.add_credential(user_id, %{
        credential_id: credential_id,
        public_key: der,
        cose_alg: -7,
        sign_count: Keyword.get(opts, :sign_count, 0),
        nickname: "test key"
      })

    %{credential: credential, private_key: private, credential_id: credential_id}
  end

  @doc "Builds and signs an assertion the way an authenticator would."
  def assertion(private_key, opts \\ []) do
    rp_id = Keyword.get(opts, :rp_id, "localhost")
    origin = Keyword.get(opts, :origin, "http://localhost:4000")
    challenge = Keyword.get(opts, :challenge, :crypto.strong_rand_bytes(32))
    sign_count = Keyword.get(opts, :sign_count, 1)
    flags = Keyword.get(opts, :flags, 0x05)

    auth_data = :crypto.hash(:sha256, rp_id) <> <<flags::8, sign_count::32>>

    client_data_json =
      Jason.encode!(%{
        "type" => "webauthn.get",
        "challenge" => WebAuthn.b64(challenge),
        "origin" => origin
      })

    message = auth_data <> :crypto.hash(:sha256, client_data_json)
    signature = :public_key.sign(message, :sha256, private_key)

    {%{
       authenticator_data: auth_data,
       client_data_json: client_data_json,
       signature: signature
     }, %{challenge: challenge, origin: origin, rp_id: rp_id}}
  end
end
