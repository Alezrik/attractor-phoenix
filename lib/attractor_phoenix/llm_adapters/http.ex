defmodule AttractorPhoenix.LLMAdapters.HTTP do
  @moduledoc false

  alias AttractorEx.LLM.Error
  alias Req.Response

  @spec post_json(String.t(), [{String.t(), String.t()}], map(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def post_json(url, headers, payload, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    req = req_module()

    case req.post(url, headers: headers, json: payload) do
      {:ok, %Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Response{status: status, body: body, headers: response_headers}} ->
        {:error,
         Error.from_http_response(provider, status, body, headers_to_map(response_headers))}

      {:error, exception} ->
        {:error, Error.transport(provider, exception)}
    end
  end

  @spec post_json_stream(String.t(), [{String.t(), String.t()}], map(), keyword()) ::
          {:ok, %{body: String.t(), headers: map(), status: pos_integer()}} | {:error, Error.t()}
  def post_json_stream(url, headers, payload, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    req = req_module()
    {:ok, collector} = Agent.start_link(fn -> [] end)

    into = fn {:data, data}, {request, response} ->
      Agent.update(collector, fn chunks -> [data | chunks] end)
      {:cont, {request, response}}
    end

    result =
      try do
        req.post(url, headers: headers, json: payload, into: into)
      after
        :ok
      end

    chunks =
      collector
      |> Agent.get(fn values -> Enum.reverse(values) end)
      |> IO.iodata_to_binary()

    Agent.stop(collector)

    case result do
      {:ok, %Response{status: status, body: body, headers: response_headers}}
      when status in 200..299 ->
        streamed_body =
          cond do
            is_binary(chunks) and chunks != "" -> chunks
            is_binary(body) -> body
            true -> ""
          end

        {:ok,
         %{
           body: streamed_body,
           headers: headers_to_map(response_headers),
           status: status
         }}

      {:ok, %Response{status: status, body: body, headers: response_headers}} ->
        {:error,
         Error.from_http_response(provider, status, body, headers_to_map(response_headers))}

      {:error, exception} ->
        {:error, Error.transport(provider, exception)}
    end
  end

  defp req_module do
    Application.get_env(:attractor_phoenix, :llm_provider_req, Req)
  end

  defp headers_to_map(headers) when is_map(headers), do: headers

  defp headers_to_map(headers) when is_list(headers) do
    Enum.into(headers, %{}, fn
      {name, value} when is_binary(name) ->
        {String.downcase(name), List.wrap(value)}

      other ->
        {inspect(other), []}
    end)
  end

  defp headers_to_map(_headers), do: %{}
end
