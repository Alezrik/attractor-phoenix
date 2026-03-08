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

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
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

  test "local execution env handles missing files, direct file grep, and absolute paths" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    env = LocalExecutionEnvironment.new(working_dir: tmp_dir)
    absolute_path = Path.join(tmp_dir, "absolute.txt")
    File.write!(absolute_path, "Alpha\nbeta\n")

    assert {:error, :enoent} = ExecutionEnvironment.read_file(env, "missing.txt")
    assert :ok = ExecutionEnvironment.write_file(env, absolute_path, "Alpha\nbeta\n")
    assert {:ok, ["absolute.txt"]} = ExecutionEnvironment.glob(env, "*.txt")

    assert {:ok, [%{line_number: 1, path: "absolute.txt"}]} =
             ExecutionEnvironment.grep(env, "Alpha",
               path: "absolute.txt",
               case_sensitive: true,
               max_results: 5
             )

    assert {:ok, []} =
             ExecutionEnvironment.grep(env, "alpha",
               path: "absolute.txt",
               case_sensitive: true,
               max_results: 5
             )
  end

  test "local execution env lists the working directory with sorted entry types" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "b-dir"))
    File.write!(Path.join(tmp_dir, "a-file.txt"), "alpha")

    env = LocalExecutionEnvironment.new(working_dir: tmp_dir)

    assert {:ok, entries} = ExecutionEnvironment.list_directory(env, ".")

    assert Enum.map(entries, & &1.name) == ["a-file.txt", "b-dir"]
    assert Enum.find(entries, &(&1.name == "a-file.txt")).type == "file"
    assert Enum.find(entries, &(&1.name == "b-dir")).type == "directory"
    assert Enum.map(entries, & &1.path) == ["a-file.txt", "b-dir"]
  end

  test "local execution env grep respects max_results across multiple matches" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "attractor-agent-env-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "matches.txt"), "hit\nhit\nhit\nmiss\n")

    env = LocalExecutionEnvironment.new(working_dir: tmp_dir)

    assert {:ok, matches} =
             ExecutionEnvironment.grep(env, "hit",
               path: "matches.txt",
               case_sensitive: true,
               max_results: 2
             )

    assert length(matches) == 2
    assert Enum.map(matches, & &1.line_number) == [1, 2]
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
    assert profile.supports_reasoning
    assert profile.supports_streaming
    assert profile.supports_parallel_tool_calls
    assert is_integer(profile.context_window_size)
    assert "read_file" in tool_names
    assert "shell" in tool_names
    assert "apply_patch" in tool_names
    assert "spawn_agent" in tool_names
  end

  test "provider profiles can register custom tools and override defaults" do
    overriding_shell =
      %Tool{
        name: "shell",
        description: "custom shell",
        parameters: %{},
        execute: fn _args, _env -> "custom" end
      }

    audit_tool =
      %Tool{
        name: "audit",
        description: "audit",
        parameters: %{},
        execute: fn _args, _env -> "ok" end
      }

    profile =
      ProviderProfile.openai(model: "gpt-5-codex")
      |> ProviderProfile.register_tool(overriding_shell)
      |> ProviderProfile.register_tool(audit_tool)

    tool_names = Enum.map(profile.tools, & &1.name)

    assert "audit" in tool_names
    assert Enum.count(tool_names, &(&1 == "shell")) == 1
    assert ProviderProfile.tool_definitions(profile) |> Enum.any?(&(&1.name == "audit"))
    assert profile.tool_registry["shell"].description == "custom shell"
  end

  test "anthropic and gemini presets preserve provider-specific metadata" do
    anthropic = ProviderProfile.anthropic(model: "claude-sonnet")
    gemini = ProviderProfile.gemini(model: "gemini-2.5-pro")
    gemini_with_web = ProviderProfile.gemini(model: "gemini-2.5-pro", web_tools: true)

    assert anthropic.id == "anthropic"
    assert anthropic.provider_family == :anthropic
    assert anthropic.preset == :anthropic
    assert gemini.id == "gemini"
    assert gemini.provider_family == :gemini
    assert gemini.preset == :gemini
    assert "web_search" in Enum.map(gemini_with_web.tools, & &1.name)
    assert "web_fetch" in Enum.map(gemini_with_web.tools, & &1.name)
  end

  test "provider profile helper metadata covers provider-specific and generic fallbacks" do
    generic_tool = %Tool{
      name: "echo",
      description: "",
      parameters: %{},
      execute: fn _args, _env -> "" end
    }

    generic =
      ProviderProfile.new(
        id: "custom",
        model: "custom-model",
        tools: [generic_tool]
      )

    assert ProviderProfile.instruction_files(generic) == ["AGENTS.md"]

    assert ProviderProfile.reasoning_option_path(generic) == [
             "provider_options",
             "reasoning_effort"
           ]

    assert ProviderProfile.reference_tool_names(generic) == ["echo"]
    assert ProviderProfile.system_prompt_style(generic) == "generic"
  end

  test "provider integration matrix includes reasoning paths and prompt styles" do
    matrix = ProviderProfile.integration_matrix()
    openai = Enum.find(matrix, &(&1.id == "openai"))
    anthropic = Enum.find(matrix, &(&1.id == "anthropic"))
    gemini = Enum.find(matrix, &(&1.id == "gemini"))

    assert openai.supports_reasoning
    assert openai.supports_streaming
    assert openai.reasoning_option_path == ["provider_options", "reasoning", "effort"]
    assert openai.system_prompt_style == "codex-rs-aligned"
    assert anthropic.reasoning_option_path == ["provider_options", "anthropic", "thinking"]
    assert anthropic.system_prompt_style == "Claude Code-aligned"
    assert gemini.reasoning_option_path == ["provider_options", "gemini", "thinkingConfig"]
    assert gemini.system_prompt_style == "gemini-cli-aligned"
  end

  test "provider presets expose provider-aligned tool names" do
    openai = BuiltinTools.for_provider(:openai) |> Enum.map(& &1.name)
    anthropic = BuiltinTools.for_provider(:anthropic) |> Enum.map(& &1.name)
    gemini = BuiltinTools.for_provider(:gemini) |> Enum.map(& &1.name)

    assert "apply_patch" in openai
    assert "shell" in openai
    assert "edit_file" in anthropic
    assert "read_many_files" in gemini
    assert "list_dir" in gemini
    refute "list_directory" in anthropic
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
    assert prompt =~ "PromptProfile=codex-rs-aligned"
    assert prompt =~ "SupportsReasoning=true"
    assert prompt =~ "SupportsStreaming=true"
    assert prompt =~ "Platform=unix-linux"
    assert prompt =~ "AvailableTools=read_file, shell_command"
    assert prompt =~ "FILE /tmp/project/AGENTS.md"
    assert prompt =~ "Follow repo rules"
    assert prompt =~ "SubagentToolsAvailable="
  end

  test "provider prompts include provider-specific guidance" do
    openai = ProviderProfile.build_system_prompt(ProviderProfile.openai(model: "gpt-5-codex"), [])

    anthropic =
      ProviderProfile.build_system_prompt(ProviderProfile.anthropic(model: "claude-sonnet"), [])

    gemini =
      ProviderProfile.build_system_prompt(ProviderProfile.gemini(model: "gemini-2.5-pro"), [])

    assert openai =~ "Use apply_patch"
    assert anthropic =~ "old_string must identify a unique match"
    assert gemini =~ "Follow GEMINI.md guidance"
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
