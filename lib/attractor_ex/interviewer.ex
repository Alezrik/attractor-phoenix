defmodule AttractorEx.Interviewer do
  @moduledoc """
  Behaviour for human-in-the-loop adapters used by `wait.human`.

  Interviewers can source answers from a console, queue, callback, HTTP workflow, or
  any custom adapter that implements the callbacks below.
  """

  @callback ask(AttractorEx.Node.t(), list(map()), map(), keyword()) ::
              {:ok, term()}
              | {:timeout}
              | {:skip}
              | {:error, term()}
              | term()
              | nil

  @callback ask_multiple(AttractorEx.Node.t(), list(map()), map(), keyword()) ::
              {:ok, list(term())}
              | {:timeout}
              | {:skip}
              | {:error, term()}
              | term()
              | nil

  @callback inform(AttractorEx.Node.t(), map(), map(), keyword()) ::
              :ok | {:ok, term()} | {:error, term()} | term()

  @optional_callbacks ask_multiple: 4, inform: 4
end
