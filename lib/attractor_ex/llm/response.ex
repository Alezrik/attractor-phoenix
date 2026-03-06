defmodule AttractorEx.LLM.Response do
  @moduledoc false

  alias AttractorEx.LLM.Usage

  defstruct text: "",
            usage: %Usage{},
            finish_reason: "stop",
            raw: %{}

  @type t :: %__MODULE__{
          text: String.t(),
          usage: Usage.t(),
          finish_reason: String.t(),
          raw: map()
        }
end
