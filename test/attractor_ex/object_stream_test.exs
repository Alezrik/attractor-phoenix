defmodule AttractorEx.LLM.ObjectStreamTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{ObjectStream, Response, StreamEvent}

  test "emits object deltas for full JSON documents and ignores duplicate documents" do
    events =
      [
        %StreamEvent{type: :text_delta, text: "{\"ok\":true}"},
        %StreamEvent{type: :response, response: %Response{text: "{\"ok\":true}"}},
        %StreamEvent{type: :stream_end}
      ]
      |> ObjectStream.insert_object_events()
      |> Enum.to_list()

    assert Enum.any?(
             events,
             &match?(%StreamEvent{type: :object_delta, object: %{"ok" => true}}, &1)
           )

    assert Enum.any?(events, &match?(%StreamEvent{type: :stream_end}, &1))
  end

  test "emits object deltas for newline-delimited chunks and ignores invalid lines" do
    events =
      [
        %StreamEvent{
          type: :text_delta,
          text: "{\"step\":1}\ninvalid\n{\"step\":2}\n"
        }
      ]
      |> ObjectStream.insert_object_events()
      |> Enum.to_list()

    assert Enum.any?(
             events,
             &match?(%StreamEvent{type: :object_delta, object: %{"step" => 1}}, &1)
           )

    assert Enum.any?(
             events,
             &match?(%StreamEvent{type: :object_delta, object: %{"step" => 2}}, &1)
           )
  end

  test "passes through non-structured events unchanged" do
    marker = {:other, :event}
    assert [^marker] = ObjectStream.insert_object_events([marker]) |> Enum.to_list()
  end
end
