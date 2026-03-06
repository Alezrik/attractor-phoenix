defmodule AttractorEx.Outcome do
  @moduledoc false

  @type status :: :success | :partial_success | :fail | :retry
  @type t :: %__MODULE__{
          status: status(),
          notes: String.t() | nil,
          failure_reason: String.t() | nil,
          context_updates: map(),
          preferred_label: String.t() | nil,
          suggested_next_ids: list(String.t())
        }

  defstruct status: :success,
            notes: nil,
            failure_reason: nil,
            context_updates: %{},
            preferred_label: nil,
            suggested_next_ids: []

  def success(updates \\ %{}, notes \\ nil),
    do: %__MODULE__{status: :success, notes: notes, context_updates: updates}

  def partial_success(updates \\ %{}, notes \\ nil),
    do: %__MODULE__{status: :partial_success, notes: notes, context_updates: updates}

  def fail(reason),
    do: %__MODULE__{status: :fail, failure_reason: to_string(reason), context_updates: %{}}

  def retry(reason),
    do: %__MODULE__{status: :retry, failure_reason: to_string(reason), context_updates: %{}}
end
