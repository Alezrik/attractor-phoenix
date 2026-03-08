defmodule AttractorEx.Agent.Tool do
  @moduledoc """
  Definition of a callable tool exposed to an agent session.
  """

  defstruct name: "", description: "", parameters: %{}, execute: nil

  @type executor :: (map(), term() -> String.t() | map() | list() | term())
  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: map(),
          execute: executor()
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
