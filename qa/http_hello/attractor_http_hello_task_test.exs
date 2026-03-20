defmodule Mix.Tasks.Attractor.Http.HelloTest do
  use ExUnit.Case, async: true

  test "uses Noor Halden's hello world tests when no arguments are passed" do
    assert Mix.Tasks.Attractor.Http.Hello.resolve_test_args([]) ==
             Mix.Tasks.Attractor.Http.Hello.default_targets()
  end

  test "appends the hello world tests when only mix test flags are passed" do
    assert Mix.Tasks.Attractor.Http.Hello.resolve_test_args(["--trace"]) ==
             ["--trace" | Mix.Tasks.Attractor.Http.Hello.default_targets()]
  end

  test "preserves explicitly targeted hello world test files" do
    args = ["--trace", "qa/http_hello/http_hello_world_test.exs"]

    assert Mix.Tasks.Attractor.Http.Hello.resolve_test_args(args) == args
  end
end
