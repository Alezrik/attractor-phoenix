defmodule AttractorExPhx.Client do
  @moduledoc """
  Req-based client for the `AttractorEx` HTTP control plane.

  This module is intentionally Phoenix-friendly: LiveViews, controllers, and other
  OTP processes can call it without depending on `AttractorPhoenix`-specific glue.
  """

  @default_timeout 5_000
  @graph_formats ~w(svg json dot mermaid text)

  def list_pipelines do
    get_json("/pipelines")
  end

  def create_pipeline(dot, context, opts \\ []) when is_binary(dot) and is_map(context) do
    post_json("/pipelines", %{
      dot: dot,
      context: context,
      opts: Enum.into(opts, %{})
    })
  end

  def run_pipeline(dot, context, opts \\ []) when is_binary(dot) and is_map(context) do
    post_json("/run", %{
      dot_source: dot,
      context: context,
      opts: Enum.into(opts, %{})
    })
  end

  def get_pipeline(id), do: get_json("/pipelines/#{id}")
  def get_status(id), do: get_json("/status?pipeline_id=#{URI.encode(id)}")
  def get_pipeline_context(id), do: get_json("/pipelines/#{id}/context")
  def get_pipeline_checkpoint(id), do: get_json("/pipelines/#{id}/checkpoint")
  def get_pipeline_questions(id), do: get_json("/pipelines/#{id}/questions")
  def get_pipeline_events(id), do: get_json("/pipelines/#{id}/events?stream=false")
  def cancel_pipeline(id), do: post_json("/pipelines/#{id}/cancel", %{})

  def answer_pipeline_question(id, question_id, answer) do
    post_json("/pipelines/#{id}/questions/#{question_id}/answer", %{answer: answer})
  end

  def answer_question(id, question_id, answer) do
    post_json("/answer", %{pipeline_id: id, question_id: question_id, value: answer})
  end

  def get_pipeline_graph_svg(id) do
    get_binary("/pipelines/#{id}/graph")
  end

  def get_pipeline_graph(id, format) when format in @graph_formats do
    case format do
      "json" -> get_json("/pipelines/#{id}/graph?format=json")
      other -> get_binary("/pipelines/#{id}/graph?format=#{other}")
    end
  end

  def get_pipeline_graph_json(id), do: get_pipeline_graph(id, "json")
  def get_pipeline_graph_dot(id), do: get_pipeline_graph(id, "dot")
  def get_pipeline_graph_mermaid(id), do: get_pipeline_graph(id, "mermaid")
  def get_pipeline_graph_text(id), do: get_pipeline_graph(id, "text")

  defp get_json(path) do
    case request(:get, path, nil) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp get_binary(path) do
    case request(:get, path, nil) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp post_json(path, body) do
    case request(:post, path, body) do
      {:ok, %{status: status, body: response_body}}
      when status in 200..299 and is_map(response_body) ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, error_message(status, response_body)}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp request(method, path, body) do
    req =
      Req.new(
        base_url: base_url(),
        connect_options: [timeout: @default_timeout],
        receive_timeout: @default_timeout
      )

    options =
      [method: method, url: path]
      |> maybe_put_body(body)

    Req.request(req, options)
  end

  defp maybe_put_body(options, nil), do: options
  defp maybe_put_body(options, body), do: Keyword.put(options, :json, body)

  defp base_url do
    Application.fetch_env!(:attractor_phoenix, :attractor_http)
    |> Keyword.fetch!(:base_url)
  end

  defp error_message(status, %{"error" => message}), do: "HTTP #{status}: #{message}"
  defp error_message(status, body), do: "HTTP #{status}: #{inspect(body)}"
end
