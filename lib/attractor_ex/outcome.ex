defmodule AttractorEx.Outcome do
  @moduledoc """
  Standard result value returned by node handlers.

  Outcomes tell the engine whether a stage succeeded, partially succeeded, failed, or
  should be retried. They also carry context updates and routing hints such as
  `preferred_label` and `suggested_next_ids`.
  """

  @type status :: :success | :partial_success | :fail | :retry
  @type failure_category :: :retryable | :terminal | :pipeline | nil
  @type t :: %__MODULE__{
          status: status(),
          notes: String.t() | nil,
          failure_reason: String.t() | nil,
          failure_category: failure_category(),
          context_updates: map(),
          preferred_label: String.t() | nil,
          suggested_next_ids: list(String.t())
        }

  defstruct status: :success,
            notes: nil,
            failure_reason: nil,
            failure_category: nil,
            context_updates: %{},
            preferred_label: nil,
            suggested_next_ids: []

  @doc "Builds a success outcome with optional context updates and notes."
  def success(updates \\ %{}, notes \\ nil),
    do: %__MODULE__{status: :success, notes: notes, context_updates: updates}

  @doc "Builds a partial-success outcome with optional context updates and notes."
  def partial_success(updates \\ %{}, notes \\ nil),
    do: %__MODULE__{status: :partial_success, notes: notes, context_updates: updates}

  @doc "Builds a failure outcome with a reason and failure category."
  def fail(reason, category \\ :terminal),
    do: %__MODULE__{
      status: :fail,
      failure_reason: to_string(reason),
      failure_category: category,
      context_updates: %{}
    }

  @doc "Builds a retry outcome with a reason and retry category."
  def retry(reason, category \\ :retryable),
    do: %__MODULE__{
      status: :retry,
      failure_reason: to_string(reason),
      failure_category: category,
      context_updates: %{}
    }
end
