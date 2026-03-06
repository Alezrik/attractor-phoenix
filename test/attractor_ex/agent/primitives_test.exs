defmodule AttractorEx.Agent.PrimitivesTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Agent.{
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
end
