defmodule AttractorPhoenix.AttractorAPI do
  @moduledoc false

  defdelegate list_pipelines(), to: AttractorExPhx.Client
  defdelegate create_pipeline(dot, context, opts \\ []), to: AttractorExPhx.Client
  defdelegate run_pipeline(dot, context, opts \\ []), to: AttractorExPhx.Client
  defdelegate get_pipeline(id), to: AttractorExPhx.Client
  defdelegate get_status(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_context(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_checkpoint(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_questions(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_events(id), to: AttractorExPhx.Client
  defdelegate cancel_pipeline(id), to: AttractorExPhx.Client
  defdelegate answer_pipeline_question(id, question_id, answer), to: AttractorExPhx.Client
  defdelegate answer_question(id, question_id, answer), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph_svg(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph(id, format), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph_json(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph_dot(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph_mermaid(id), to: AttractorExPhx.Client
  defdelegate get_pipeline_graph_text(id), to: AttractorExPhx.Client
end
