defmodule AttractorEx.Interviewer do
  @moduledoc false

  @callback ask(AttractorEx.Node.t(), list(map()), map(), keyword()) ::
              {:ok, term()}
              | {:timeout}
              | {:skip}
              | {:error, term()}
              | term()
              | nil
end
