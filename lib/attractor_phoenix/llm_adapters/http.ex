defmodule AttractorPhoenix.LLMAdapters.HTTP do
  @moduledoc false

  def post_json(url, headers, payload) do
    req = Application.get_env(:attractor_phoenix, :llm_provider_req, Req)

    case req.post(url, headers: headers, json: payload) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
        {:error, "HTTP #{status}: #{inspect(error)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, format_exception(exception)}
    end
  end

  defp format_exception(%_{} = exception), do: Exception.message(exception)
  defp format_exception(other), do: inspect(other)
end
