defmodule NerdMeet.AccountsTest do
  use NerdMeet.DataCase, async: true

  alias NerdMeet.Accounts
  alias NerdMeet.Accounts.Risk
  alias NerdMeet.Fixtures

  describe "registration" do
    test "an adult with a valid certificate is verified on the spot" do
      assert {:ok, user} =
               Accounts.register(%{
                 "handle" => "hjosugi",
                 "identity" => %{"serial" => "abc", "birth_year" => 1990}
               })

      assert user.status == "active"
      assert user.verified_at
      assert user.birth_year == 1990
    end

    test "the certificate serial is stored only as a hash" do
      {:ok, user} =
        Accounts.register(%{
          "handle" => "hashed",
          "identity" => %{"serial" => "serial-12345", "birth_year" => 1990}
        })

      assert byte_size(user.identity_serial_hash) == 32
      refute String.contains?(user.identity_serial_hash, "serial-12345")
    end

    test "the same certificate cannot register twice" do
      identity = %{"serial" => "same-card", "birth_year" => 1990}

      {:ok, _first} = Accounts.register(%{"handle" => "first", "identity" => identity})

      assert {:error, changeset} =
               Accounts.register(%{"handle" => "second", "identity" => identity})

      assert "この本人確認書類は既に登録されています" in errors_on(changeset).identity_serial_hash
    end

    test "a minor is refused before any row is written" do
      assert {:error, :under_age} =
               Accounts.register(%{
                 "handle" => "tooyoung",
                 "identity" => %{"serial" => "x", "birth_year" => Date.utc_today().year - 15}
               })

      assert is_nil(Accounts.get_user_by_handle("tooyoung"))
    end
  end

  describe "authentication" do
    setup do
      user = Fixtures.member()
      %{user: user, key: Fixtures.passkey(user.id)}
    end

    test "a valid assertion from a known place is allowed with no friction",
         %{key: key} do
      {assertion, expectation} = Fixtures.assertion(key.private_key, sign_count: 1)

      assert {:ok, _user, assessment} =
               Accounts.authenticate(key.credential_id, assertion, expectation, %{
                 country: "JP"
               })

      assert assessment.score == 0
      assert assessment.decision == :allow
    end

    test "a tampered signature is rejected", %{key: key} do
      {assertion, expectation} = Fixtures.assertion(key.private_key, sign_count: 1)
      tampered = %{assertion | signature: :crypto.strong_rand_bytes(70)}

      assert {:error, :bad_signature} =
               Accounts.authenticate(key.credential_id, tampered, expectation)
    end

    test "a replayed challenge from another origin is rejected", %{key: key} do
      {assertion, expectation} = Fixtures.assertion(key.private_key, sign_count: 1)

      assert {:error, :client_data_mismatch} =
               Accounts.authenticate(key.credential_id, assertion, %{
                 expectation
                 | origin: "https://evil.example"
               })
    end

    test "a counter that fails to advance revokes every credential",
         %{user: user, key: key} do
      {first, expectation} = Fixtures.assertion(key.private_key, sign_count: 5)
      {:ok, _user, _assessment} = Accounts.authenticate(key.credential_id, first, expectation)

      # The same counter again: two copies of the key material exist.
      {replay, replay_expectation} = Fixtures.assertion(key.private_key, sign_count: 5)

      assert {:error, :credential_cloned} =
               Accounts.authenticate(key.credential_id, replay, replay_expectation)

      assert Accounts.list_credentials(user.id) == []

      [latest | _rest] = Accounts.list_auth_events(user.id)
      assert latest.decision == "revoke_all"
      assert latest.risk_score == 100
    end
  end

  describe "risk scoring" do
    test "a familiar country and device costs nothing" do
      user = %{last_country: "JP", last_latitude: 35.68, last_longitude: 139.69}

      assessment =
        Risk.assess(user, %{country: "JP", latitude: 35.68, longitude: 139.69}, nil)

      assert assessment.score == 0
      assert assessment.decision == :allow
    end

    test "a new country plus impossible travel demands re-authentication" do
      user = %{
        last_country: "JP",
        last_latitude: 35.68,
        last_longitude: 139.69,
        last_seen_at: DateTime.utc_now()
      }

      assessment =
        Risk.assess(
          user,
          %{country: "BR", latitude: -23.55, longitude: -46.63, at: DateTime.utc_now()},
          nil
        )

      assert "country_change" in assessment.reasons
      assert "impossible_travel" in assessment.reasons
      assert assessment.score == 100
      assert assessment.decision == :step_up
    end

    test "travel that an aircraft could have made is not suspicious" do
      earlier = DateTime.shift(DateTime.utc_now(), hour: -20)

      user = %{
        last_country: "JP",
        last_latitude: 35.68,
        last_longitude: 139.69,
        last_seen_at: earlier
      }

      assessment =
        Risk.assess(user, %{country: "JP", latitude: 33.59, longitude: 130.40}, nil)

      refute "impossible_travel" in assessment.reasons
      assert assessment.decision == :allow
    end

    test "a first-time authenticator alone is not enough to demand a second factor" do
      assessment = Risk.assess(%{last_country: "JP"}, %{country: "JP", new_credential: true})

      assert assessment.score < Risk.step_up_threshold()
      assert assessment.decision == :allow
    end
  end
end
