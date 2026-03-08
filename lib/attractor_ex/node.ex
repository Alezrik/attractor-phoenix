defmodule AttractorEx.Node do
  @moduledoc """
  Runtime representation of a pipeline node.

  Nodes keep the original attribute map and the normalized fields that drive execution,
  such as shape, handler type, prompt, goal-gate status, and retry targets.
  """

  @shape_to_type %{
    "Mdiamond" => "start",
    "Msquare" => "exit",
    "diamond" => "conditional",
    "component" => "parallel",
    "tripleoctagon" => "parallel.fan_in",
    "hexagon" => "wait.human",
    "parallelogram" => "tool",
    "house" => "stack.manager_loop",
    "box" => "codergen"
  }

  defstruct id: nil,
            attrs: %{},
            shape: "box",
            type: "codergen",
            prompt: "",
            goal_gate: false,
            retry_target: nil,
            fallback_retry_target: nil

  @type t :: %__MODULE__{
          id: String.t(),
          attrs: map(),
          shape: String.t(),
          type: String.t(),
          prompt: String.t(),
          goal_gate: boolean(),
          retry_target: String.t() | nil,
          fallback_retry_target: String.t() | nil
        }

  def new(id, attrs) do
    shape = normalize_shape(Map.get(attrs, "shape", "box"))
    type = Map.get(attrs, "type") || Map.get(@shape_to_type, shape, "codergen")

    %__MODULE__{
      id: id,
      attrs: attrs,
      shape: shape,
      type: type,
      prompt: Map.get(attrs, "prompt", ""),
      goal_gate: truthy?(Map.get(attrs, "goal_gate", false)),
      retry_target: blank_to_nil(Map.get(attrs, "retry_target")),
      fallback_retry_target: blank_to_nil(Map.get(attrs, "fallback_retry_target"))
    }
  end

  @doc "Returns the default handler type implied by a Graphviz shape."
  def handler_type_for_shape(shape),
    do: Map.get(@shape_to_type, normalize_shape(shape), "codergen")

  defp normalize_shape(nil), do: "box"
  defp normalize_shape(shape), do: String.trim(to_string(shape))

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp truthy?(value) when is_boolean(value), do: value

  defp truthy?(value) when is_binary(value),
    do: String.downcase(String.trim(value)) in ["true", "1", "yes"]

  defp truthy?(_), do: false
end
