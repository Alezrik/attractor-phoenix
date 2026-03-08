defmodule AttractorEx.Agent.Tool do
  @moduledoc """
  Definition of a callable tool exposed to an agent session.

  Tools default to `target: :environment`, meaning their executor receives the
  current execution environment. Session-managed tools such as subagent lifecycle
  operations set `target: :session` and receive the current session instead.
  """

  defstruct name: "", description: "", parameters: %{}, execute: nil, target: :environment

  @type target :: :environment | :session
  @type executor :: (map(), term() -> String.t() | map() | list() | term())
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          execute: executor(),
          target: target()
        }

  @spec definition(t()) :: map()
  @doc "Serializes a tool into the model-facing definition shape."
  def definition(%__MODULE__{} = tool) do
    %{
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters
    }
  end
end
