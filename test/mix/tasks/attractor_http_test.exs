defmodule Mix.Tasks.Attractor.HttpTest do
  use ExUnit.Case, async: true

  test "uses the maintained HTTP API suite when no arguments are passed" do
    assert Mix.Tasks.Attractor.Http.resolve_test_args([]) ==
             Mix.Tasks.Attractor.Http.default_targets()
  end

  test "appends the maintained HTTP API suite when only mix test flags are passed" do
    assert Mix.Tasks.Attractor.Http.resolve_test_args(["--trace"]) ==
             ["--trace" | Mix.Tasks.Attractor.Http.default_targets()]
  end

  test "preserves explicitly targeted test files" do
    args = ["--trace", "test/attractor_ex/http_test.exs"]

    assert Mix.Tasks.Attractor.Http.resolve_test_args(args) == args
  end

  test "preserves explicitly targeted test directories" do
    args = ["test/attractor_ex/conformance"]

    assert Mix.Tasks.Attractor.Http.resolve_test_args(args) == args
  end
end
