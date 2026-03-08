defmodule AttractorEx.Agent.PrimitivesTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{
    BuiltinTools,
    ExecutionEnvironment,
    LocalExecutionEnvironment,
    ProviderProfile,
    SessionConfig,
    Tool,
    ToolRegistry
  }

  test "local execution env resolves cwd and platform" do
    env = LocalExecutionEnvironment.new()
    assert is_binary(LocalExecutionEnvironment.working_directory(env))
    assert String.contains?(LocalExecutionEnvironment.platform(env), "-")
  end

  test "local execution env supports file, glob, grep, and shell primitives" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    env = LocalExecutionEnvironment.new(working_dir: tmp_dir)

    assert :ok =
             ExecutionEnvironment.write_file(
               env,
               "nested/example.txt",
               "hello agent\nsecond line"
             )

    assert {:ok, "hello agent\nsecond line"} =
             ExecutionEnvironment.read_file(env, "nested/example.txt")

    assert {:ok, entries} = ExecutionEnvironment.list_directory(env, "nested")
    assert Enum.any?(entries, &(&1.name == "example.txt" and &1.type == "file"))

    assert {:ok, ["nested/example.txt"]} = ExecutionEnvironment.glob(env, "**/*.txt")

    assert {:ok, matches} = ExecutionEnvironment.grep(env, "hello", path: ".", max_results: 10)
    assert Enum.any?(matches, &(&1.path == "nested/example.txt"))

    assert {:ok, %{exit_code: 0, output: output}} =
             ExecutionEnvironment.shell_command(
               env,
               shell_echo_command("hi from shell"),
               timeout_ms: 1_000
             )

    assert output =~ "hi from shell"
  end

  test "local execution env reports environment context and shell truncation" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    env = LocalExecutionEnvironment.new(working_dir: tmp_dir, env: %{"FOO" => "bar"})

    assert %{available_env_vars: ["FOO"], working_directory: ^tmp_dir} =
             ExecutionEnvironment.environment_context(env)

    assert {:ok, %{truncated?: true, output: output}} =
             ExecutionEnvironment.shell_command(
               env,
               shell_repeat_command(200),
               timeout_ms: 1_000,
               max_output_bytes: 20
             )

    assert output =~ "truncated"
  end

  test "local execution env returns shell timeout and missing directory errors" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    env = LocalExecutionEnvironment.new(working_dir: tmp_dir)

    assert {:error, :timeout} =
             ExecutionEnvironment.shell_command(
               env,
               shell_sleep_command(200),
               timeout_ms: 1
             )

    assert {:error, _reason} = ExecutionEnvironment.list_directory(env, "missing")
  end

  test "provider profile supports custom prompt builder" do
    profile =
      ProviderProfile.new(
        id: "openai",
        model: "gpt-5.2",
        tools: [],
        system_prompt_builder: fn context -> "wd=#{context[:working_dir]}" end
      )

    prompt = ProviderProfile.build_system_prompt(profile, working_dir: "/tmp/project")
    assert prompt == "wd=/tmp/project"
  end

  test "provider preset bundles built-in tools and capability metadata" do
    profile = ProviderProfile.openai(model: "gpt-5-codex")
    tool_names = Enum.map(profile.tools, & &1.name)

    assert profile.id == "openai"
    assert profile.provider_family == :openai
    assert profile.supports_parallel_tool_calls
    assert is_integer(profile.context_window_size)
    assert "read_file" in tool_names
    assert "shell_command" in tool_names
  end

  test "anthropic and gemini presets preserve provider-specific metadata" do
    anthropic = ProviderProfile.anthropic(model: "claude-sonnet")
    gemini = ProviderProfile.gemini(model: "gemini-2.5-pro")

    assert anthropic.id == "anthropic"
    assert anthropic.provider_family == :anthropic
    assert anthropic.preset == :anthropic
    assert gemini.id == "gemini"
    assert gemini.provider_family == :gemini
    assert gemini.preset == :gemini
  end

  test "built-in tool bundle is available across provider presets" do
    tool_names =
      BuiltinTools.for_provider(:anthropic)
      |> Enum.map(& &1.name)

    assert Enum.sort(tool_names) ==
             Enum.sort([
               "glob",
               "grep",
               "list_directory",
               "read_file",
               "shell_command",
               "write_file"
             ])
  end

  test "tool registry register and get" do
    tool = %Tool{
      name: "echo",
      description: "",
      parameters: %{},
      execute: fn _args, _env -> "" end
    }

    registry =
      []
      |> ToolRegistry.from_tools()
      |> ToolRegistry.register(tool)

    assert %Tool{name: "echo"} = ToolRegistry.get(registry, "echo")
  end

  test "session config merges partial tool output limit overrides with defaults" do
    config = SessionConfig.new(tool_output_limits: %{"shell_command" => 123})

    assert config.tool_output_limits["shell_command"] == 123
    assert is_integer(config.tool_output_limits["__default__"])
    assert config.tool_output_limits["__default__"] > 0
  end

  test "default provider prompt includes environment context and project instructions" do
    prompt =
      ProviderProfile.build_system_prompt(
        ProviderProfile.openai(model: "gpt-5-codex"),
        working_dir: "/tmp/project",
        platform: "unix-linux",
        tool_names: ["read_file", "shell_command"],
        environment_context: %{working_directory: "/tmp/project"},
        project_docs: [%{path: "/tmp/project/AGENTS.md", content: "Follow repo rules"}],
        date: "2026-03-07"
      )

    assert prompt =~ "Provider=openai"
    assert prompt =~ "Platform=unix-linux"
    assert prompt =~ "AvailableTools=read_file, shell_command"
    assert prompt =~ "FILE /tmp/project/AGENTS.md"
    assert prompt =~ "Follow repo rules"
  end

  defp shell_echo_command(text) do
    case :os.type() do
      {:win32, _} -> "Write-Output '#{text}'"
      _ -> "printf '%s\\n' '#{text}'"
    end
  end

  defp shell_repeat_command(count) do
    case :os.type() do
      {:win32, _} -> "Write-Output ('x' * #{count})"
      _ -> "printf 'x%.0s' $(seq 1 #{count})"
    end
  end

  defp shell_sleep_command(milliseconds) do
    case :os.type() do
      {:win32, _} -> "Start-Sleep -Milliseconds #{milliseconds}"
      _ -> "sleep #{milliseconds / 1000}"
    end
  end
end
