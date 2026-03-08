defmodule AttractorEx.LLM.Client do
  @moduledoc """
  Provider-agnostic LLM client used by codergen nodes and agent sessions.

  The client resolves providers, applies middleware, delegates to adapter modules, and
  supports both request/response and streaming flows.
  """

  alias AttractorEx.LLM.Request

  defstruct providers: %{}, default_provider: nil, middleware: [], streaming_middleware: []

  @type middleware :: (Request.t(), (Request.t() -> any()) -> any())

  @type t :: %__MODULE__{
          providers: %{optional(String.t()) => module()},
          default_provider: String.t() | nil,
          middleware: [middleware()],
          streaming_middleware: [middleware()]
        }

  @doc "Executes a completion request and returns either a response or an error tuple."
  def complete(%__MODULE__{} = client, %Request{} = request) do
    case complete_with_request(client, request) do
      {:ok, response, _resolved_request} -> response
      {:error, _reason} = error -> error
    end
  end

  @doc "Executes a completion request and also returns the resolved request."
  def complete_with_request(%__MODULE__{} = client, %Request{} = request) do
    run_with_middleware(client.middleware, request, fn req ->
      with {:ok, provider_name} <- resolve_provider(client, req),
           {:ok, adapter} <- fetch_adapter(client, provider_name) do
        resolved_request = %{req | provider: provider_name}

        case adapter.complete(resolved_request) do
          {:error, _reason} = error -> error
          response -> {:ok, response, resolved_request}
        end
      end
    end)
    |> normalize_complete_result(request)
  end

  @doc "Executes a streaming request and returns the event stream or an error tuple."
  def stream(%__MODULE__{} = client, %Request{} = request) do
    case stream_with_request(client, request) do
      {:ok, events, _resolved_request} -> events
      {:error, _reason} = error -> error
    end
  end

  @doc "Executes a streaming request and also returns the resolved request."
  def stream_with_request(%__MODULE__{} = client, %Request{} = request) do
    run_with_middleware(client.streaming_middleware, request, fn req ->
      with {:ok, provider_name} <- resolve_provider(client, req),
           {:ok, adapter} <- fetch_adapter(client, provider_name) do
        resolved_request = %{req | provider: provider_name}

        cond do
          not adapter_supports_stream?(adapter) ->
            {:error, {:stream_not_supported, provider_name}}

          true ->
            case adapter.stream(resolved_request) do
              {:error, _reason} = error -> error
              events -> {:ok, events, resolved_request}
            end
        end
      end
    end)
    |> normalize_complete_result(request)
  end

  defp adapter_supports_stream?(adapter) do
    Code.ensure_loaded?(adapter) and function_exported?(adapter, :stream, 1)
  end

  defp normalize_complete_result(
         {:ok, _response, %Request{} = _resolved_request} = result,
         _request
       ),
       do: result

  defp normalize_complete_result({:error, _reason} = error, _request), do: error

  defp normalize_complete_result(response, %Request{} = request) do
    # Allow middleware short-circuit returning a response directly.
    {:ok, response, request}
  end

  defp resolve_provider(client, request) do
    provider = blank_to_nil(request.provider) || blank_to_nil(client.default_provider)

    if is_binary(provider) do
      {:ok, provider}
    else
      {:error, :provider_not_configured}
    end
  end

  defp fetch_adapter(client, provider_name) do
    case Map.get(client.providers, provider_name) do
      nil -> {:error, {:provider_not_registered, provider_name}}
      adapter -> {:ok, adapter}
    end
  end

  defp run_with_middleware([], request, call), do: call.(request)

  defp run_with_middleware([middleware | rest], request, call) when is_function(middleware, 2) do
    middleware.(request, fn req -> run_with_middleware(rest, req, call) end)
  end

  defp run_with_middleware([_ | rest], request, call),
    do: run_with_middleware(rest, request, call)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
