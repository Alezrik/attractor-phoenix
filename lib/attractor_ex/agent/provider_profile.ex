defmodule AttractorEx.Agent.ProviderProfile do
  @moduledoc """
  Provider-aligned configuration for the coding-agent loop.

  A profile packages a model, toolset, provider options, and an optional system-prompt
  builder so agent sessions can stay portable across providers.
  """

  alias AttractorEx.Agent.{Tool, ToolRegistry}

  defstruct id: "",
            model: "",
            supports_parallel_tool_calls: false,
            tools: [],
            tool_registry: %{},
            provider_options: %{},
            system_prompt_builder: nil

  @type t :: %__MODULE__{
          id: String.t(),
          model: String.t(),
          supports_parallel_tool_calls: boolean(),
          tools: [Tool.t()],
          tool_registry: ToolRegistry.t(),
          provider_options: map(),
          system_prompt_builder: (keyword() -> String.t()) | nil
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
      tools: tools,
      tool_registry: tool_registry,
      provider_options: Keyword.get(opts, :provider_options, %{}),
      system_prompt_builder: Keyword.get(opts, :system_prompt_builder)
    }
  end

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
      working_dir = context[:working_dir] || "."
      date = context[:date] || Date.utc_today() |> Date.to_iso8601()
      "You are a coding agent. Model=#{profile.model}. WorkingDir=#{working_dir}. Date=#{date}."
    end
  end
end
