defmodule AttractorEx.HandlerRegistry do
  @moduledoc """
  Resolves node types to executable handler modules.

  The registry includes the built-in handlers required by the runtime and supports
  dynamic extension through `register/2`.
  """

  alias AttractorEx.{Handlers, Node}

  @base_handlers %{
    "start" => Handlers.Start,
    "exit" => Handlers.Exit,
    "codergen" => Handlers.Codergen,
    "conditional" => Handlers.Conditional,
    "parallel" => Handlers.Parallel,
    "parallel.fan_in" => Handlers.ParallelFanIn,
    "tool" => Handlers.Tool,
    "wait.human" => Handlers.WaitForHuman,
    "wait_for_human" => Handlers.WaitForHuman,
    "stack.manager_loop" => Handlers.StackManagerLoop
  }

  @registry_key {__MODULE__, :handlers}

  @doc "Registers a handler module for an explicit type string."
  def register(type_string, handler_module)
      when is_binary(type_string) and is_atom(handler_module) do
    handlers = Map.put(dynamic_handlers(), type_string, handler_module)
    :persistent_term.put(@registry_key, handlers)
    :ok
  end

  @doc "Resolves the effective handler module for a node."
  def resolve(node) do
    handlers = dynamic_handlers()
    explicit_type = blank_to_nil(Map.get(node.attrs, "type"))

    cond do
      is_binary(explicit_type) and Map.has_key?(handlers, explicit_type) ->
        Map.fetch!(handlers, explicit_type)

      Map.has_key?(handlers, Node.handler_type_for_shape(node.shape)) ->
        Map.fetch!(handlers, Node.handler_type_for_shape(node.shape))

      true ->
        Handlers.Codergen
    end
  end

  @doc "Alias for `resolve/1`."
  def handler_for(node), do: resolve(node)

  @doc "Returns whether a type string is known to the registry."
  def known_type?(type) when is_binary(type) do
    Map.has_key?(dynamic_handlers(), String.trim(type))
  end

  def known_type?(_type), do: false

  defp dynamic_handlers do
    :persistent_term.get(@registry_key, @base_handlers)
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
