defmodule AttractorEx.Agent.BuiltinToolsTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{BuiltinTools, ExecutionEnvironment, LocalExecutionEnvironment}

  test "built-in tools perform common filesystem and shell operations" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:default))

    assert "1 | seed" == run_tool(tools["read_file"], %{"path" => "seed.txt"}, env)

    assert "Wrote nested/output.txt (5 bytes)" ==
             run_tool(
               tools["write_file"],
               %{"path" => "nested/output.txt", "content" => "hello"},
               env
             )

    directory_listing = run_tool(tools["list_directory"], %{"path" => "nested"}, env)
    assert directory_listing =~ "\"name\":\"output.txt\""

    glob_output = run_tool(tools["glob"], %{"pattern" => "**/*.txt"}, env)
    assert glob_output =~ "nested/output.txt"
    assert glob_output =~ "seed.txt"

    grep_output =
      run_tool(tools["grep"], %{"pattern" => "hello", "path" => ".", "max_results" => 5}, env)

    assert grep_output =~ "\"path\":\"nested/output.txt\""

    shell_output =
      run_tool(
        tools["shell_command"],
        %{"command" => shell_echo_command("hello shell"), "timeout_ms" => 1_000},
        env
      )

    assert shell_output =~ "exit_code=0"
    assert shell_output =~ "hello shell"
  end

  test "built-in grep respects case sensitivity" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:default))

    File.write!(Path.join(root, "sample.txt"), "Hello\nhello")

    output =
      run_tool(
        tools["grep"],
        %{"pattern" => "Hello", "path" => "sample.txt", "case_sensitive" => true},
        env
      )

    assert output =~ "\"line_number\":1"
    refute output =~ "\"line_number\":2"
  end

  test "read_file supports file_path aliases with offset and limit" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:openai))

    File.write!(Path.join(root, "sample.txt"), "one\ntwo\nthree\n")

    output =
      run_tool(
        tools["read_file"],
        %{"file_path" => "sample.txt", "offset" => 2, "limit" => 1},
        env
      )

    assert output == "2 | two"
  end

  test "built-in tools raise when environment is invalid" do
    tool = BuiltinTools.for_provider(:default) |> tools_by_name() |> Map.fetch!("read_file")

    assert_raise ArgumentError, ~r/ExecutionEnvironment/, fn ->
      run_tool(tool, %{"path" => "seed.txt"}, %{})
    end
  end

  test "built-in tools surface environment errors" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:default))

    assert_raise RuntimeError, ~r/read_file failed/, fn ->
      run_tool(tools["read_file"], %{"path" => "missing.txt"}, env)
    end

    assert_raise RuntimeError, ~r/shell_command failed: timeout/, fn ->
      run_tool(
        tools["shell_command"],
        %{"command" => "Start-Sleep -Milliseconds 200", "timeout_ms" => 1},
        env
      )
    end
  end

  test "provider-specific tool bundles are exposed for all supported presets" do
    openai = Enum.map(BuiltinTools.for_provider(:openai), & &1.name)
    anthropic = Enum.map(BuiltinTools.for_provider(:anthropic), & &1.name)
    gemini = Enum.map(BuiltinTools.for_provider(:gemini), & &1.name)

    assert "apply_patch" in openai
    assert "shell" in openai
    assert "edit_file" in anthropic
    assert "shell" in anthropic
    assert "read_many_files" in gemini
    assert "list_dir" in gemini
  end

  test "provider-specific editing tools run against the shared environment" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)

    anthropic = tools_by_name(BuiltinTools.for_provider(:anthropic))

    assert "Edited seed.txt (1 replacement)" ==
             run_tool(
               anthropic["edit_file"],
               %{
                 "file_path" => "seed.txt",
                 "old_string" => "seed",
                 "new_string" => "grown"
               },
               env
             )

    assert File.read!(Path.join(root, "seed.txt")) == "grown"

    gemini = tools_by_name(BuiltinTools.for_provider(:gemini))

    output = run_tool(gemini["read_many_files"], %{"paths" => ["seed.txt"]}, env)
    assert output =~ "FILE seed.txt"
    assert output =~ "1 | grown"
  end

  test "edit_file reports missing and ambiguous matches" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:anthropic))

    File.write!(Path.join(root, "sample.txt"), "same\nsame\n")

    assert_raise RuntimeError, ~r/not unique/, fn ->
      run_tool(
        tools["edit_file"],
        %{
          "file_path" => "sample.txt",
          "old_string" => "same",
          "new_string" => "different"
        },
        env
      )
    end

    assert_raise RuntimeError, ~r/not found/, fn ->
      run_tool(
        tools["edit_file"],
        %{
          "file_path" => "sample.txt",
          "old_string" => "missing",
          "new_string" => "different"
        },
        env
      )
    end
  end

  test "glob and grep support provider-aligned path filters" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:gemini))

    File.mkdir_p!(Path.join(root, "nested"))
    File.write!(Path.join(root, "nested/a.txt"), "Alpha")
    File.write!(Path.join(root, "nested/b.md"), "alpha")

    glob_output = run_tool(tools["glob"], %{"pattern" => "*.txt", "path" => "nested"}, env)
    assert glob_output =~ "nested/a.txt"

    grep_output =
      run_tool(
        tools["grep"],
        %{
          "pattern" => "alpha",
          "path" => "nested",
          "case_insensitive" => true,
          "glob_filter" => "**/*.txt"
        },
        env
      )

    assert grep_output =~ "\"path\":\"nested/a.txt\""
    refute grep_output =~ "\"path\":\"nested/b.md\""
  end

  test "shell alias and apply_patch surface provider-specific failures" do
    anthropic = tools_by_name(BuiltinTools.for_provider(:anthropic))
    openai = tools_by_name(BuiltinTools.for_provider(:openai))

    assert_raise RuntimeError, ~r/shell failed: timeout/, fn ->
      run_tool(
        anthropic["shell"],
        %{"command" => "echo hi", "timeout_ms" => 1},
        %AttractorExTest.ExecutionEnv{mode: :shell_timeout}
      )
    end

    assert_raise RuntimeError,
                 ~r/apply_patch failed: apply_patch requires LocalExecutionEnvironment/,
                 fn ->
                   run_tool(
                     openai["apply_patch"],
                     %{"patch" => "*** Begin Patch\n*** End Patch"},
                     %AttractorExTest.ExecutionEnv{}
                   )
                 end
  end

  test "list_dir and shell surface provider-specific non-timeout failures" do
    gemini = tools_by_name(BuiltinTools.for_provider(:gemini))
    anthropic = tools_by_name(BuiltinTools.for_provider(:anthropic))

    assert_raise RuntimeError, ~r/list_dir failed/, fn ->
      run_tool(gemini["list_dir"], %{}, %AttractorExTest.ExecutionEnv{mode: :list_error})
    end

    assert_raise RuntimeError, ~r/shell failed: :failed/, fn ->
      run_tool(
        anthropic["shell"],
        %{"command" => "echo hi"},
        %AttractorExTest.ExecutionEnv{mode: :shell_error}
      )
    end
  end

  test "openai apply_patch updates files using v4a patch format" do
    root = tmp_dir()
    env = LocalExecutionEnvironment.new(working_dir: root)
    tools = tools_by_name(BuiltinTools.for_provider(:openai))

    patch = """
    *** Begin Patch
    *** Update File: seed.txt
    @@
    -seed
    +sprout
    *** End Patch
    """

    output = run_tool(tools["apply_patch"], %{"patch" => patch}, env)

    assert output =~ "\"operation\":\"update\""
    assert File.read!(Path.join(root, "seed.txt")) == "sprout"
  end

  test "built-in bundle includes session-managed subagent tools" do
    tools = tools_by_name(BuiltinTools.for_provider(:default))

    assert tools["spawn_agent"].target == :session
    assert tools["send_input"].target == :session
    assert tools["wait"].target == :session
    assert tools["close_agent"].target == :session
  end

  test "built-in tools surface non-timeout environment failures" do
    tools = tools_by_name(BuiltinTools.for_provider(:default))

    assert_raise RuntimeError, ~r/write_file failed/, fn ->
      run_tool(
        tools["write_file"],
        %{"path" => "x", "content" => "y"},
        %AttractorExTest.ExecutionEnv{
          mode: :write_error
        }
      )
    end

    assert_raise RuntimeError, ~r/list_directory failed/, fn ->
      run_tool(tools["list_directory"], %{}, %AttractorExTest.ExecutionEnv{mode: :list_error})
    end

    assert_raise RuntimeError, ~r/glob failed/, fn ->
      run_tool(tools["glob"], %{"pattern" => "*"}, %AttractorExTest.ExecutionEnv{
        mode: :glob_error
      })
    end

    assert_raise RuntimeError, ~r/grep failed/, fn ->
      run_tool(tools["grep"], %{"pattern" => "a"}, %AttractorExTest.ExecutionEnv{
        mode: :grep_error
      })
    end

    assert_raise RuntimeError, ~r/shell_command failed: :failed/, fn ->
      run_tool(
        tools["shell_command"],
        %{"command" => "echo hi"},
        %AttractorExTest.ExecutionEnv{mode: :shell_error}
      )
    end
  end

  test "execution environment wrappers dispatch to implementations and reject invalid values" do
    env = %AttractorExTest.ExecutionEnv{}

    assert ExecutionEnvironment.implementation?(env)
    assert ExecutionEnvironment.working_directory(env) == "/tmp/fake"
    assert ExecutionEnvironment.platform(env) == "test-platform"
    assert {:ok, "fake-content"} = ExecutionEnvironment.read_file(env, "a.txt")
    assert :ok = ExecutionEnvironment.write_file(env, "a.txt", "body")
    assert {:ok, [%{name: "file.txt"}]} = ExecutionEnvironment.list_directory(env, ".")
    assert {:ok, ["file.txt"]} = ExecutionEnvironment.glob(env, "*")
    assert {:ok, [%{path: "file.txt"}]} = ExecutionEnvironment.grep(env, "match", [])
    assert {:ok, %{exit_code: 0}} = ExecutionEnvironment.shell_command(env, "echo ok", [])
    assert %{test: true} = ExecutionEnvironment.environment_context(env)
    refute ExecutionEnvironment.implementation?(%{})

    assert_raise ArgumentError, ~r/ExecutionEnvironment implementation/, fn ->
      ExecutionEnvironment.working_directory(%{})
    end
  end

  defp run_tool(tool, args, env) do
    tool.execute.(args, env)
  end

  defp tools_by_name(tools) do
    Map.new(tools, fn tool -> {tool.name, tool} end)
  end

  defp tmp_dir do
    root =
      Path.join(System.tmp_dir!(), "attractor-builtins-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "seed.txt"), "seed")
    root
  end

  defp shell_echo_command(text) do
    case :os.type() do
      {:win32, _} -> "Write-Output '#{text}'"
      _ -> "printf '%s\\n' '#{text}'"
    end
  end
end
