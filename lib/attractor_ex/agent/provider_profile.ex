defmodule AttractorEx.Agent.ProviderProfile do
  @moduledoc """
  Provider-aligned configuration for the coding-agent loop.

  A profile packages a model, toolset, provider options, and an optional system-prompt
  builder so agent sessions can stay portable across providers.

  The module also exposes a maintained cross-provider integration matrix for the
  built-in OpenAI, Anthropic, and Gemini presets.
  """

  alias AttractorEx.Agent.{BuiltinTools, Event, Tool, ToolRegistry}

  defstruct id: "",
            model: "",
            supports_parallel_tool_calls: false,
            context_window_size: nil,
            provider_family: :generic,
            tools: [],
            tool_registry: %{},
            provider_options: %{},
            system_prompt_builder: nil,
            preset: nil

  @type t :: %__MODULE__{
          id: String.t(),
          model: String.t(),
          supports_parallel_tool_calls: boolean(),
          context_window_size: pos_integer() | nil,
          provider_family: atom(),
          tools: [Tool.t()],
          tool_registry: ToolRegistry.t(),
          provider_options: map(),
          system_prompt_builder: (keyword() -> String.t()) | nil,
          preset: atom() | nil
        }

  @type integration_entry :: %{
          id: String.t(),
          provider_family: atom(),
          preset: atom(),
          implemented_tool_names: [String.t()],
          reference_tool_names: [String.t()],
          instruction_files: [String.t()],
          reasoning_option_path: [String.t()],
          system_prompt_style: String.t(),
          event_kinds: [Event.kind()]
        }

  @spec new(keyword()) :: t()
  @doc "Builds a provider profile from keyword options."
  def new(opts) do
    tools = Keyword.get(opts, :tools, [])
    tool_registry = Keyword.get(opts, :tool_registry, ToolRegistry.from_tools(tools))

    %__MODULE__{
      id: Keyword.get(opts, :id, ""),
      model: Keyword.get(opts, :model, ""),
      supports_parallel_tool_calls: Keyword.get(opts, :supports_parallel_tool_calls, false),
      context_window_size: Keyword.get(opts, :context_window_size),
      provider_family: Keyword.get(opts, :provider_family, :generic),
      tools: tools,
      tool_registry: tool_registry,
      provider_options: Keyword.get(opts, :provider_options, %{}),
      system_prompt_builder: Keyword.get(opts, :system_prompt_builder),
      preset: Keyword.get(opts, :preset)
    }
  end

  @spec openai(keyword()) :: t()
  def openai(opts \\ []) do
    default_tools = BuiltinTools.for_provider(:openai)

    new(
      [
        id: "openai",
        provider_family: :openai,
        supports_parallel_tool_calls: true,
        context_window_size: 400_000,
        preset: :openai,
        tools: default_tools
      ] ++ opts
    )
  end

  @spec anthropic(keyword()) :: t()
  def anthropic(opts \\ []) do
    default_tools = BuiltinTools.for_provider(:anthropic)

    new(
      [
        id: "anthropic",
        provider_family: :anthropic,
        supports_parallel_tool_calls: true,
        context_window_size: 200_000,
        preset: :anthropic,
        tools: default_tools
      ] ++ opts
    )
  end

  @spec gemini(keyword()) :: t()
  def gemini(opts \\ []) do
    default_tools = BuiltinTools.for_provider(:gemini)

    new(
      [
        id: "gemini",
        provider_family: :gemini,
        supports_parallel_tool_calls: true,
        context_window_size: 1_000_000,
        preset: :gemini,
        tools: default_tools
      ] ++ opts
    )
  end

  @spec integration_matrix() :: [integration_entry()]
  @doc "Returns the maintained cross-provider integration matrix for built-in presets."
  def integration_matrix do
    for profile <- [openai(), anthropic(), gemini()] do
      %{
        id: profile.id,
        provider_family: profile.provider_family,
        preset: profile.preset,
        implemented_tool_names: Enum.map(profile.tools, & &1.name),
        reference_tool_names: reference_tool_names(profile),
        instruction_files: instruction_files(profile),
        reasoning_option_path: reasoning_option_path(profile),
        system_prompt_style: system_prompt_style(profile),
        event_kinds: Event.supported_kinds()
      }
    end
  end

  @spec instruction_files(t()) :: [String.t()]
  @doc "Returns the project-instruction files relevant to the active provider profile."
  def instruction_files(%__MODULE__{id: "anthropic"}), do: ["AGENTS.md", "CLAUDE.md"]
  def instruction_files(%__MODULE__{id: "gemini"}), do: ["AGENTS.md", "GEMINI.md"]

  def instruction_files(%__MODULE__{id: "openai"}),
    do: ["AGENTS.md", "CODEX.md", ".codex/instructions.md"]

  def instruction_files(%__MODULE__{}), do: ["AGENTS.md"]

  @spec reasoning_option_path(t()) :: [String.t()]
  @doc "Returns the provider-native request path associated with reasoning/thinking controls."
  def reasoning_option_path(%__MODULE__{id: "anthropic"}),
    do: ["provider_options", "anthropic", "thinking"]

  def reasoning_option_path(%__MODULE__{id: "gemini"}),
    do: ["provider_options", "gemini", "thinkingConfig"]

  def reasoning_option_path(%__MODULE__{id: "openai"}),
    do: ["provider_options", "reasoning", "effort"]

  def reasoning_option_path(%__MODULE__{}), do: ["provider_options", "reasoning_effort"]

  @spec reference_tool_names(t()) :: [String.t()]
  @doc "Returns the upstream native tool names the preset is intended to align with."
  def reference_tool_names(%__MODULE__{id: "anthropic"}) do
    [
      "read_file",
      "write_file",
      "edit_file",
      "shell",
      "grep",
      "glob",
      "spawn_agent",
      "send_input",
      "wait",
      "close_agent"
    ]
  end

  def reference_tool_names(%__MODULE__{id: "gemini"}) do
    [
      "read_file",
      "read_many_files",
      "write_file",
      "edit_file",
      "shell",
      "grep",
      "glob",
      "list_dir",
      "web_search",
      "web_fetch",
      "spawn_agent",
      "send_input",
      "wait",
      "close_agent"
    ]
  end

  def reference_tool_names(%__MODULE__{id: "openai"}) do
    [
      "read_file",
      "apply_patch",
      "write_file",
      "shell",
      "grep",
      "glob",
      "spawn_agent",
      "send_input",
      "wait",
      "close_agent"
    ]
  end

  def reference_tool_names(%__MODULE__{} = profile), do: Enum.map(profile.tools, & &1.name)

  @spec system_prompt_style(t()) :: String.t()
  @doc "Returns the reference-agent prompt family used as the preset target."
  def system_prompt_style(%__MODULE__{id: "anthropic"}), do: "Claude Code-aligned"
  def system_prompt_style(%__MODULE__{id: "gemini"}), do: "gemini-cli-aligned"
  def system_prompt_style(%__MODULE__{id: "openai"}), do: "codex-rs-aligned"
  def system_prompt_style(%__MODULE__{}), do: "generic"

  @spec tool_definitions(t()) :: [map()]
  @doc "Returns the serialized tool definitions exposed to the model."
  def tool_definitions(%__MODULE__{} = profile) do
    Enum.map(profile.tools, &Tool.definition/1)
  end

  @spec build_system_prompt(t(), keyword()) :: String.t()
  @doc "Builds the system prompt for a session request."
  def build_system_prompt(%__MODULE__{} = profile, context) do
    builder = profile.system_prompt_builder

    if is_function(builder, 1) do
      builder.(context)
    else
      default_system_prompt(profile, context)
    end
  end

  defp default_system_prompt(%__MODULE__{} = profile, context) do
    working_dir = context[:working_dir] || "."
    date = context[:date] || Date.utc_today() |> Date.to_iso8601()
    platform = context[:platform] || "unknown"
    tool_names = context[:tool_names] || Enum.map(profile.tools, & &1.name)
    environment_context = context[:environment_context] || %{}
    project_docs = context[:project_docs] || []
    doc_section = render_project_docs(project_docs)

    lines =
      [
        "You are a coding agent.",
        "Provider=#{profile.id}",
        "Model=#{profile.model}",
        "WorkingDir=#{working_dir}",
        "Platform=#{platform}",
        "Date=#{date}",
        "ParallelToolCalls=#{profile.supports_parallel_tool_calls}",
        "AvailableTools=#{Enum.join(tool_names, ", ")}",
        "EnvironmentContext=#{Jason.encode!(environment_context)}",
        "SubagentToolsAvailable=#{Enum.any?(tool_names, &(&1 in ["spawn_agent", "send_input", "wait", "close_agent"]))}"
      ] ++ doc_section

    Enum.join(lines, "\n")
  end

  defp render_project_docs([]), do: []

  defp render_project_docs(project_docs) do
    ["ProjectInstructions:"] ++
      Enum.flat_map(project_docs, fn doc ->
        [
          "FILE #{doc.path}",
          doc.content
        ]
      end)
  end
end
