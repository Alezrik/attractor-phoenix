defmodule AttractorExTest.RetryThenSuccessBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(node, _prompt, _context) do
    key = {__MODULE__, node.id}
    attempts = Process.get(key, 0)
    Process.put(key, attempts + 1)

    if node.id == "task" and attempts < 2 do
      Outcome.retry("try again")
    else
      Outcome.success(%{"retry_attempts" => attempts + 1})
    end
  end
end
