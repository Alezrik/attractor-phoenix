defmodule AttractorEx.InterviewerPayloadTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Interviewers.Payload
  alias AttractorEx.Node

  test "question builds normalized metadata for freeform nodes" do
    node =
      %Node{
        id: "gate",
        attrs: %{
          "prompt" => "Explain your choice",
          "human.timeout" => "30s",
          "human.required" => "false",
          "human.input" => " text "
        }
      }

    question = Payload.question(node, [])

    assert question.id == "gate"
    assert question.text == "Explain your choice"
    assert question.type == "FREEFORM"
    assert question.timeout_seconds == 30.0
    assert question.multiple == false
    assert question.required == false
    assert question.metadata["input_mode"] == "text"
    assert question.metadata["choice_count"] == 0
  end

  test "question_type and input_mode infer confirmation yes-no and multi-select shapes" do
    confirm_node = %Node{id: "confirm", attrs: %{}}
    yes_no_node = %Node{id: "approve", attrs: %{}}
    multiple_node = %Node{id: "multi", attrs: %{"human.multiple" => true}}

    assert Payload.question_type(confirm_node, [%{key: "C", label: "Confirm", to: "done"}]) ==
             "CONFIRMATION"

    assert Payload.question_type(yes_no_node, [
             %{key: "Y", label: "Yes", to: "approved"},
             %{key: "N", label: "No", to: "rejected"}
           ]) == "YES_NO"

    assert Payload.question_type(multiple_node, [%{key: "A"}, %{key: "B"}]) ==
             "MULTIPLE_CHOICE"

    assert Payload.input_mode(confirm_node, "CONFIRMATION", [%{"key" => "C"}]) == "confirmation"

    assert Payload.input_mode(yes_no_node, "YES_NO", [%{"key" => "Y"}, %{"key" => "N"}]) ==
             "boolean"

    assert Payload.input_mode(%Node{id: "single", attrs: %{}}, "MULTIPLE_CHOICE", [
             %{"key" => "A"}
           ]) ==
             "single_select"

    assert Payload.input_mode(%Node{id: "multi", attrs: %{}}, "MULTIPLE_CHOICE", [
             %{"key" => "A"},
             %{"key" => "B"}
           ]) ==
             "multi_select"
  end

  test "timeout_ms handles units integers and invalid values" do
    assert Payload.timeout_ms(1500) == 1500
    assert Payload.timeout_ms("45") == 45_000
    assert Payload.timeout_ms("250ms") == 250
    assert Payload.timeout_ms("2s") == 2_000
    assert Payload.timeout_ms("3m") == 180_000
    assert Payload.timeout_ms("1h") == 3_600_000
    assert Payload.timeout_ms("1d") == 86_400_000
    assert Payload.timeout_ms("bogus") == 60_000
    assert Payload.timeout_ms(nil) == 60_000
  end

  test "normalize_choice and normalize_token handle maps scalars and booleans" do
    assert Payload.normalize_choice(%{key: "A", label: "Approve", to: "done"}) == %{
             "key" => "A",
             "label" => "Approve",
             "to" => "done"
           }

    assert Payload.normalize_choice("raw") == %{"value" => "raw"}
    assert Payload.normalize_token(true) == "true"
    assert Payload.normalize_token(false) == "false"
    assert Payload.normalize_token(nil) == ""
    assert Payload.normalize_token("  YES ") == "yes"
  end

  test "extract_answer finds common structured answer keys" do
    assert Payload.extract_answer(%{"answers" => ["A"]}) == ["A"]
    assert Payload.extract_answer(%{values: ["B"]}) == ["B"]
    assert Payload.extract_answer(%{"selected" => "C"}) == "C"
    assert Payload.extract_answer(%{selection: "D"}) == "D"
    assert Payload.extract_answer(%{"answer" => "E"}) == "E"
    assert Payload.extract_answer(%{value: "F"}) == "F"
    assert Payload.extract_answer(%{"key" => "G"}) == "G"
    assert Payload.extract_answer(%{keys: ["H"]}) == ["H"]
    assert Payload.extract_answer("plain") == nil
  end

  test "normalize_single_answer handles yes-no confirmation and plain values" do
    yes_no = %{id: "q1", type: "YES_NO", multiple: false, required: true, options: []}
    confirmation = %{id: "q2", type: "CONFIRMATION", multiple: false, required: true, options: []}
    freeform = %{id: "q3", type: "FREEFORM", multiple: false, required: true, options: []}

    assert Payload.normalize_single_answer("approved", yes_no) == "yes"
    assert Payload.normalize_single_answer(false, yes_no) == "no"
    assert Payload.normalize_single_answer(%{"answer" => "confirm"}, confirmation) == "confirm"
    assert Payload.normalize_single_answer(%{"answer" => "no"}, confirmation) == "cancel"
    assert Payload.normalize_single_answer(%{"answer" => "  ship it  "}, freeform) == "ship it"
  end

  test "normalize_multiple_answer handles nested lists and structured values" do
    question = %{id: "q1", type: "MULTIPLE_CHOICE", multiple: true, required: true, options: []}

    assert Payload.normalize_multiple_answer([" A ", %{"value" => "B"}], question) == ["A", "B"]

    assert Payload.normalize_multiple_answer(%{"selected" => [%{"key" => "A"}, "B"]}, question) ==
             ["A", "B"]
  end

  test "answer_payload returns matched options for normalized answers" do
    question = %{
      id: "gate",
      type: "MULTIPLE_CHOICE",
      multiple: true,
      required: true,
      options: [
        %{"key" => "A", "label" => "Approve", "to" => "approved"},
        %{"key" => "F", "label" => "Fix", "to" => "fixes"}
      ],
      metadata: %{"input_mode" => "multi_select"}
    }

    payload = Payload.answer_payload(%{"selected" => [%{"key" => "A"}, "fixes"]}, question)

    assert payload.question_id == "gate"
    assert payload.multiple == true
    assert payload.values == ["A", "fixes"]
    assert Enum.map(payload.matched_options, & &1["to"]) == ["approved", "fixes"]
  end

  test "message and parse_console_input normalize display and json payloads" do
    assert Payload.message(%{"message" => "Heads up"}) == "Heads up"
    assert Payload.message(%{message: "Heads up"}) == "Heads up"
    assert Payload.message(:ok) == "ok"

    assert Payload.parse_console_input("") == ""
    assert Payload.parse_console_input("  [1, 2] ") == [1, 2]
    assert Payload.parse_console_input(~s({"answer":"A"})) == %{"answer" => "A"}
    assert Payload.parse_console_input("{not-json}") == "{not-json}"
    assert Payload.parse_console_input("  plain text  ") == "plain text"
  end

  test "multiple_choice and required predicates normalize booleans and strings" do
    assert Payload.multiple_choice?(%Node{id: "a", attrs: %{"human.multiple" => "yes"}})
    refute Payload.multiple_choice?(%Node{id: "b", attrs: %{"human.multiple" => "no"}})

    assert Payload.required?(%Node{id: "c", attrs: %{}})
    assert Payload.required?(%Node{id: "d", attrs: %{"human.required" => "true"}})
    refute Payload.required?(%Node{id: "e", attrs: %{"human.required" => "false"}})
    assert Payload.required?(%Node{id: "f", attrs: %{"human.required" => "maybe"}})
  end
end
