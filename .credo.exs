# Credo runs in --strict mode in CI. Two default thresholds are raised, each
# for a specific reason rather than to make the build pass.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: %{
        extra: [
          # A rule cascade is a `cond` with one branch per rule. Splitting it
          # into helper functions to satisfy a complexity metric would hide the
          # order the rules are applied in, which is the part that matters.
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
          # Ecto.Multi callbacks and `with` bodies are naturally one level
          # deeper than the default allows.
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]}
        ],
        disabled: []
      }
    }
  ]
}
