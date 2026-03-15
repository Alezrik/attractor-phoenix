defmodule AttractorEx.HTTP.RunStore do
  @moduledoc """
  Behaviour for durable HTTP runtime storage.
  """

  alias AttractorEx.HTTP.{EventRecord, QuestionRecord, RunRecord}

  @type config :: term()
  @type loaded_run :: %{
          run: RunRecord.t(),
          events: [EventRecord.t()],
          questions: [QuestionRecord.t()]
        }

  @callback init(keyword()) :: {:ok, config()}
  @callback list_runs(config()) :: {:ok, [loaded_run()]} | {:error, term()}
  @callback put_run(config(), RunRecord.t()) :: :ok | {:error, term()}
  @callback append_event(config(), String.t(), EventRecord.t()) :: :ok | {:error, term()}
  @callback put_questions(config(), String.t(), [QuestionRecord.t()]) :: :ok | {:error, term()}
  @callback list_events(config(), String.t(), keyword()) ::
              {:ok, [EventRecord.t()]} | {:error, term()}
end
