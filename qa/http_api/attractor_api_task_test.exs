defmodule Mix.Tasks.Attractor.ApiTest do
  use ExUnit.Case, async: true

  test "uses Noor Halden's maintained API smoke tests when no arguments are passed" do
    assert Mix.Tasks.Attractor.Api.resolve_test_args([]) ==
             Mix.Tasks.Attractor.Api.default_targets()
  end

  test "appends the API smoke tests when only mix test flags are passed" do
    assert Mix.Tasks.Attractor.Api.resolve_test_args(["--trace"]) ==
             ["--trace" | Mix.Tasks.Attractor.Api.default_targets()]
  end

  test "preserves explicitly targeted API smoke files" do
    args = ["--trace", "qa/http_api/api_smoke_test.exs"]

    assert Mix.Tasks.Attractor.Api.resolve_test_args(args) == args
  end
end
