defmodule AttractorPhoenixTest.DotGeneratorAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Message, Request, Response, Usage}

  def complete(%Request{} = request) do
    user_prompt =
      request.messages
      |> Enum.find_value(fn
        %Message{role: :user, content: content} -> Message.content_text(content)
        _ -> nil
      end)

    dot =
      cond do
        String.contains?(user_prompt || "", "explode output") ->
          raise "adapter exploded while generating dot"

        String.contains?(user_prompt || "", "noisy output") ->
          """
          Codex session starting...
          Planning graph generation

          digraph generated_pipeline {
            graph [goal="Ship a generated pipeline", label="Generated Pipeline"]
            start [shape=Mdiamond, label="Start"]
            plan [shape=box, label="Plan", prompt="Plan for $goal", llm_model="#{request.model}"]
            done [shape=Msquare, label="Done"]
            start -> plan
            plan -> done
          }

          Generation complete.
          """

        String.contains?(user_prompt || "", "wrapped output") ->
          """
          Here is the pipeline DOT you asked for:

          ```dot
          digraph generated_pipeline {
            graph [goal="Ship a generated pipeline", label="Generated Pipeline"]
            start [shape=Mdiamond, label="Start"]
            plan [shape=box, label="Plan", prompt="Plan for $goal", llm_model="#{request.model}"]
            done [shape=Msquare, label="Done"]
            start -> plan
            plan -> done
          }
          ```

          This follows the simple example pattern.
          """

        String.contains?(user_prompt || "", "broken") ->
          "not actually dot"

        true ->
          """
          digraph generated_pipeline {
            graph [goal="Ship a generated pipeline", label="Generated Pipeline"]
            start [shape=Mdiamond, label="Start"]
            plan [shape=box, label="Plan", prompt="Plan for $goal", llm_model="#{request.model}"]
            done [shape=Msquare, label="Done"]
            start -> plan
            plan -> done
          }
          """
      end

    %Response{
      text: dot,
      finish_reason: "stop",
      usage: %Usage{input_tokens: 10, output_tokens: 20, total_tokens: 30}
    }
  end
end
