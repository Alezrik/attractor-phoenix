defmodule AttractorEx.Edge do
  @moduledoc false

  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          attrs: map(),
          condition: String.t() | nil,
          status: String.t() | nil
        }

  defstruct from: nil, to: nil, attrs: %{}, condition: nil, status: nil

  def new(from, to, attrs) do
    %__MODULE__{
      from: from,
      to: to,
      attrs: attrs,
      condition: blank_to_nil(Map.get(attrs, "condition")),
      status: blank_to_nil(Map.get(attrs, "status") || Map.get(attrs, "outcome"))
    }
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
