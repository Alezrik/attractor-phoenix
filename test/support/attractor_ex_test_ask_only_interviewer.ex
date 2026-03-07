defmodule AttractorExTest.AskOnlyInterviewer do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(_node, _choices, _context, opts) do
    {:ok, opts[:answer]}
  end
end
