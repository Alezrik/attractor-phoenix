defmodule AttractorPhoenix.AttractorAPI do
  @moduledoc false

  @default_timeout 5_000

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

  def get_pipeline(id), do: get_json("/pipelines/#{id}")
  def get_pipeline_context(id), do: get_json("/pipelines/#{id}/context")
  def get_pipeline_checkpoint(id), do: get_json("/pipelines/#{id}/checkpoint")
  def get_pipeline_questions(id), do: get_json("/pipelines/#{id}/questions")
  def get_pipeline_events(id), do: get_json("/pipelines/#{id}/events?stream=false")

  def get_pipeline_graph_svg(id) do
    case request(:get, "/pipelines/#{id}/graph", nil) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, error_message(status, body)}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

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
