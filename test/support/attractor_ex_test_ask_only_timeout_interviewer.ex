defmodule AttractorExTest.AskOnlyTimeoutInterviewer do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(_node, _choices, _context, _opts) do
    :timeout
  end
end
