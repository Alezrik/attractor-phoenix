defmodule AttractorEx.Interviewers.Console do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(node, choices, _context, _opts) do
    prompt =
      ["Select a choice for human gate `", node.id, "`:"] ++
        Enum.map(choices, fn choice -> "\n- [#{choice.key}] #{choice.label}" end) ++
        ["\n> "]

    case IO.gets(IO.ANSI.format(prompt, true)) do
      value when is_binary(value) -> {:ok, String.trim(value)}
      _ -> {:timeout}
    end
  end
end
