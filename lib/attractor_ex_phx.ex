defmodule AttractorExPhx do
  @moduledoc """
  Phoenix-facing adapter layer for `AttractorEx`.

  `AttractorEx` remains the standalone pipeline engine. `AttractorExPhx` is the
  integration seam a Phoenix application can depend on for:

  - direct pipeline execution via `run/3`
  - supervision-friendly HTTP server startup via `child_spec/1` and `start_link/1`
  - Req-based access to the HTTP control plane via `AttractorExPhx.Client`
  """

  alias AttractorExPhx.{Client, HTTPServer}

  @spec run(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, %{diagnostics: list()}} | {:error, %{error: String.t()}}
  def run(dot, context \\ %{}, opts \\ []) when is_binary(dot) and is_map(context) do
    AttractorEx.run(dot, context, opts)
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    HTTPServer.child_spec(opts)
  end

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    HTTPServer.start_link(opts)
  end

  @spec start_http_server(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_http_server(opts \\ []) do
    HTTPServer.start_link(opts)
  end

  @spec stop_http_server(pid() | atom()) :: :ok
  def stop_http_server(server) do
    AttractorEx.stop_http_server(server)
  end

  defdelegate list_pipelines(), to: Client
  defdelegate create_pipeline(dot, context, opts \\ []), to: Client
  defdelegate run_pipeline(dot, context, opts \\ []), to: Client
  defdelegate get_pipeline(id), to: Client
  defdelegate get_status(id), to: Client
  defdelegate get_pipeline_context(id), to: Client
  defdelegate get_pipeline_checkpoint(id), to: Client
  defdelegate get_pipeline_questions(id), to: Client
  defdelegate get_pipeline_events(id), to: Client
  defdelegate cancel_pipeline(id), to: Client
  defdelegate answer_pipeline_question(id, question_id, answer), to: Client
  defdelegate answer_question(id, question_id, answer), to: Client
  defdelegate get_pipeline_graph_svg(id), to: Client
  defdelegate get_pipeline_graph(id, format), to: Client
  defdelegate get_pipeline_graph_json(id), to: Client
  defdelegate get_pipeline_graph_dot(id), to: Client
  defdelegate get_pipeline_graph_mermaid(id), to: Client
  defdelegate get_pipeline_graph_text(id), to: Client
end
