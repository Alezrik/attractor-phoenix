defmodule AttractorEx.TestGenerators do
  @moduledoc false

  use PropCheck

  def canonical_shape do
    elements([
      "Mdiamond",
      "Msquare",
      "diamond",
      "component",
      "tripleoctagon",
      "hexagon",
      "parallelogram",
      "house",
      "box"
    ])
  end

  def identifier do
    let chars <- list(integer(?a, ?z)) do
      List.to_string(chars)
    end
  end

  def nonempty_identifier do
    let chars <- list(integer(?a, ?z)) do
      case chars do
        [] -> "a"
        _ -> List.to_string(chars)
      end
    end
  end

  def whitespace_wrapped(value) when is_binary(value) do
    let [left, right] <- [list(elements([" ", "\t"])), list(elements([" ", "\t"]))] do
      Enum.join(left, "") <> value <> Enum.join(right, "")
    end
  end
end
