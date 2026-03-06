defmodule AttractorExTest.AlwaysRetryBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(_node, _prompt, _context), do: Outcome.retry("still retrying")
end
