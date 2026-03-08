defmodule AttractorEx.StatusContractPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.{Outcome, StatusContract}

  property "status_file_payload keeps outcome and status fields aligned" do
    forall [status, note] <- [elements([:success, :partial_success, :fail, :retry]), identifier()] do
      outcome = %Outcome{status: status, notes: note}
      payload = StatusContract.status_file_payload(outcome)
      expected = Atom.to_string(status)

      payload["outcome"] == expected and payload["status"] == expected and
        payload["notes"] == note
    end
  end

  property "blank preferred labels normalize to nil in the status file payload" do
    forall blank <- elements([nil, "", " ", "   ", "\t"]) do
      payload =
        StatusContract.status_file_payload(%Outcome{status: :success, preferred_label: blank})

      is_nil(payload["preferred_label"]) and is_nil(payload["preferred_next_label"])
    end
  end

  property "failure categories are stringified in the status file payload" do
    forall category <- elements([:retryable, :terminal, :pipeline]) do
      payload =
        StatusContract.status_file_payload(%Outcome{status: :fail, failure_category: category})

      payload["error_category"] == Atom.to_string(category)
    end
  end

  property "serialize_outcome preserves the raw runtime values" do
    forall [reason, preferred_label, next_id] <- [
             identifier(),
             identifier(),
             nonempty_identifier()
           ] do
      outcome = %Outcome{
        status: :retry,
        notes: "note",
        failure_reason: reason,
        failure_category: :retryable,
        context_updates: %{"retry" => true},
        preferred_label: preferred_label,
        suggested_next_ids: [next_id]
      }

      serialized = StatusContract.serialize_outcome(outcome)

      serialized.status == :retry and serialized.outcome == "retry" and
        serialized.failure_reason == reason and serialized.failure_category == :retryable and
        serialized.preferred_label == preferred_label and
        serialized.preferred_next_label == preferred_label and
        serialized.suggested_next_ids == [next_id]
    end
  end
end
