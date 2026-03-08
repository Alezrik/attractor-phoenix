defmodule AttractorEx.Agent.LocalExecutionEnvironmentFallbackTest do
  use ExUnit.Case, async: false

  alias AttractorEx.Agent.{ExecutionEnvironment, LocalExecutionEnvironment}

  test "grep falls back to elixir search when rg is unavailable" do
    original_path = System.get_env("PATH")
    System.put_env("PATH", "")

    on_exit(fn ->
      if original_path do
        System.put_env("PATH", original_path)
      else
        System.delete_env("PATH")
      end
    end)

    root =
      Path.join(
        System.tmp_dir!(),
        "attractor-agent-fallback-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "nested"))
    File.write!(Path.join(root, "nested/example.txt"), "Hello\nhello\nother")
    env = LocalExecutionEnvironment.new(working_dir: root)

    assert {:ok, file_matches} =
             ExecutionEnvironment.grep(env, "Hello",
               path: "nested/example.txt",
               case_sensitive: true
             )

    assert [%{line_number: 1, path: "nested/example.txt"}] = file_matches

    assert {:ok, dir_matches} =
             ExecutionEnvironment.grep(env, "hello", path: "nested", case_sensitive: false)

    assert Enum.count(dir_matches) == 2

    assert {:ok, []} =
             ExecutionEnvironment.grep(env, "missing",
               path: "does-not-exist",
               case_sensitive: false
             )
  end
end
