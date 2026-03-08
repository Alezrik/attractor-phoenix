defmodule AttractorEx.LLM.Client do
  @moduledoc """
  Provider-agnostic LLM client used by codergen nodes and agent sessions.

  The client resolves providers, applies middleware, delegates to adapter modules, and
  supports both request/response and streaming flows.

  Beyond the low-level `complete/2` and `stream/2` APIs, the module also exposes:

  1. `from_env/1` for runtime construction from application config
  2. module-level default-client helpers
  3. spec-aligned convenience wrappers such as `generate/2`
  4. stream accumulation helpers for callers that want a final normalized response
  5. JSON object generation helpers layered on top of the normalized response surface
  """

  alias AttractorEx.LLM.{Request, Response, StreamEvent, Usage}

  @default_client_key {__MODULE__, :default_client}
  @default_otp_app :attractor_phoenix
  @default_config_key :attractor_ex_llm

  defstruct providers: %{}, default_provider: nil, middleware: [], streaming_middleware: []

  @type middleware :: (Request.t(), (Request.t() -> any()) -> any())

  @type t :: %__MODULE__{
          providers: %{optional(String.t()) => module()},
          default_provider: String.t() | nil,
          middleware: [middleware()],
          streaming_middleware: [middleware()]
        }

  @doc "Builds a client from keyword options."
  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    %__MODULE__{
      providers: normalize_provider_map(Keyword.get(opts, :providers, %{})),
      default_provider: blank_to_nil(Keyword.get(opts, :default_provider)),
      middleware: Keyword.get(opts, :middleware, []),
      streaming_middleware: Keyword.get(opts, :streaming_middleware, [])
    }
  end

  @doc """
  Builds a client from application config, with direct opts taking precedence.

  Supported config shape:

      config :attractor_phoenix, :attractor_ex_llm,
        providers: %{"openai" => MyApp.OpenAIAdapter},
        default_provider: "openai"
  """
  @spec from_env(keyword()) :: t()
  def from_env(opts \\ []) when is_list(opts) do
    app = Keyword.get(opts, :otp_app, @default_otp_app)
    config_key = Keyword.get(opts, :config_key, @default_config_key)
    config = Application.get_env(app, config_key, [])
    config_map = config_to_map(config)

    providers =
      Keyword.get(opts, :providers) ||
        Map.get(config_map, :providers) ||
        Map.get(config_map, "providers") ||
        %{}

    default_provider =
      Keyword.get(opts, :default_provider) ||
        System.get_env("ATTRACTOR_EX_LLM_DEFAULT_PROVIDER") ||
        Map.get(config_map, :default_provider) ||
        Map.get(config_map, "default_provider")

    middleware =
      Keyword.get(opts, :middleware) ||
        Map.get(config_map, :middleware) ||
        Map.get(config_map, "middleware") ||
        []

    streaming_middleware =
      Keyword.get(opts, :streaming_middleware) ||
        Map.get(config_map, :streaming_middleware) ||
        Map.get(config_map, "streaming_middleware") ||
        []

    new(
      providers: providers,
      default_provider: default_provider,
      middleware: middleware,
      streaming_middleware: streaming_middleware
    )
  end

  @doc "Stores a module-level default client used by the arity-1 helpers."
  @spec put_default(t()) :: t()
  def put_default(%__MODULE__{} = client) do
    :persistent_term.put(@default_client_key, client)
    client
  end

  @doc "Returns the configured module-level default client, or `nil`."
  @spec default() :: t() | nil
  def default do
    case :persistent_term.get(@default_client_key, nil) do
      %__MODULE__{} = client -> client
      _ -> nil
    end
  end

  @doc "Clears the module-level default client."
  @spec clear_default() :: :ok
  def clear_default do
    :persistent_term.erase(@default_client_key)
    :ok
  end

  @doc "Executes a completion request via the configured module-level default client."
  @spec complete(Request.t()) :: Response.t() | {:error, term()}
  def complete(%Request{} = request) do
    with_default_client(fn client -> complete(client, request) end)
  end

  @doc "Executes a completion request and returns either a response or an error tuple."
  def complete(%__MODULE__{} = client, %Request{} = request) do
    case complete_with_request(client, request) do
      {:ok, response, _resolved_request} -> response
      {:error, _reason} = error -> error
    end
  end

  @doc "Spec-style completion alias for `complete/2`."
  @spec generate(Request.t()) :: Response.t() | {:error, term()}
  def generate(%Request{} = request), do: complete(request)

  @doc "Spec-style completion alias for `complete/2`."
  @spec generate(t(), Request.t()) :: Response.t() | {:error, term()}
  def generate(%__MODULE__{} = client, %Request{} = request), do: complete(client, request)

  @doc "Spec-style completion alias for `complete_with_request/2`."
  @spec generate_with_request(t(), Request.t()) ::
          {:ok, Response.t(), Request.t()} | {:error, term()}
  def generate_with_request(%__MODULE__{} = client, %Request{} = request),
    do: complete_with_request(client, request)

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

  @doc "Executes a streaming request via the configured module-level default client."
  @spec stream(Request.t()) :: Enumerable.t() | {:error, term()}
  def stream(%Request{} = request) do
    with_default_client(fn client -> stream(client, request) end)
  end

  @doc "Executes a streaming request and returns the event stream or an error tuple."
  def stream(%__MODULE__{} = client, %Request{} = request) do
    case stream_with_request(client, request) do
      {:ok, events, _resolved_request} -> events
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Consumes a raw event stream and returns a normalized final response.

  This is useful for callers that want provider streaming for latency but still need a
  single accumulated `AttractorEx.LLM.Response`.
  """
  @spec accumulate_stream(Request.t()) :: Response.t() | {:error, term()}
  def accumulate_stream(%Request{} = request) do
    with_default_client(fn client -> accumulate_stream(client, request) end)
  end

  @doc """
  Consumes a raw event stream and returns a normalized final response.
  """
  @spec accumulate_stream(t(), Request.t()) :: Response.t() | {:error, term()}
  def accumulate_stream(%__MODULE__{} = client, %Request{} = request) do
    case accumulate_stream_with_request(client, request) do
      {:ok, response, _resolved_request} -> response
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Consumes a raw event stream and returns the accumulated response plus resolved request.
  """
  @spec accumulate_stream_with_request(t(), Request.t()) ::
          {:ok, Response.t(), Request.t()} | {:error, term()}
  def accumulate_stream_with_request(%__MODULE__{} = client, %Request{} = request) do
    with {:ok, events, resolved_request} <- stream_with_request(client, request) do
      response =
        events
        |> Enum.reduce(empty_accumulated_response(), &accumulate_stream_event/2)
        |> finalize_accumulated_response()

      {:ok, response, resolved_request}
    end
  end

  @doc "Generates a JSON object via the configured module-level default client."
  @spec generate_object(Request.t()) :: {:ok, map() | list()} | {:error, term()}
  def generate_object(%Request{} = request) do
    with_default_client(fn client -> generate_object(client, request) end)
  end

  @doc """
  Generates a JSON object from a non-streaming response.

  The response body is decoded from `response.text`.
  """
  @spec generate_object(t(), Request.t()) :: {:ok, map() | list()} | {:error, term()}
  def generate_object(%__MODULE__{} = client, %Request{} = request) do
    case generate_object_with_request(client, request) do
      {:ok, object, _response, _resolved_request} -> {:ok, object}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generates a JSON object from a non-streaming response and also returns transport data.
  """
  @spec generate_object_with_request(t(), Request.t()) ::
          {:ok, map() | list(), Response.t(), Request.t()} | {:error, term()}
  def generate_object_with_request(%__MODULE__{} = client, %Request{} = request) do
    with {:ok, response, resolved_request} <- generate_with_request(client, request),
         {:ok, object} <- decode_json_response(response) do
      {:ok, object, response, resolved_request}
    end
  end

  @doc "Generates a JSON object from a streamed response via the default client."
  @spec stream_object(Request.t()) :: {:ok, map() | list()} | {:error, term()}
  def stream_object(%Request{} = request) do
    with_default_client(fn client -> stream_object(client, request) end)
  end

  @doc """
  Generates a JSON object by first accumulating a streamed response.
  """
  @spec stream_object(t(), Request.t()) :: {:ok, map() | list()} | {:error, term()}
  def stream_object(%__MODULE__{} = client, %Request{} = request) do
    case stream_object_with_request(client, request) do
      {:ok, object, _response, _resolved_request} -> {:ok, object}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Generates a JSON object by first accumulating a streamed response and also returns
  the normalized response plus resolved request.
  """
  @spec stream_object_with_request(t(), Request.t()) ::
          {:ok, map() | list(), Response.t(), Request.t()} | {:error, term()}
  def stream_object_with_request(%__MODULE__{} = client, %Request{} = request) do
    with {:ok, response, resolved_request} <- accumulate_stream_with_request(client, request),
         {:ok, object} <- decode_json_response(response) do
      {:ok, object, response, resolved_request}
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

  defp with_default_client(callback) when is_function(callback, 1) do
    case default() do
      %__MODULE__{} = client -> callback.(client)
      nil -> {:error, :default_client_not_configured}
    end
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

  defp empty_accumulated_response do
    %Response{
      text: "",
      tool_calls: [],
      reasoning: nil,
      usage: %Usage{},
      finish_reason: "stop",
      raw: %{"stream_errors" => []}
    }
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :text_delta, text: text},
         %Response{} = response
       ) do
    %{response | text: response.text <> (text || "")}
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :reasoning_delta, reasoning: reasoning},
         %Response{} = response
       ) do
    accumulated =
      case {response.reasoning, reasoning} do
        {nil, value} -> value
        {existing, value} -> (existing || "") <> (value || "")
      end

    %{response | reasoning: accumulated}
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :tool_call, tool_call: tool_call},
         %Response{} = response
       ) do
    %{response | tool_calls: response.tool_calls ++ List.wrap(tool_call)}
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :response, response: %Response{} = final_response},
         %Response{} = response
       ) do
    %Response{
      final_response
      | text:
          if(blank_string?(final_response.text), do: response.text, else: final_response.text),
        reasoning:
          if(blank_string?(final_response.reasoning),
            do: response.reasoning,
            else: final_response.reasoning
          ),
        tool_calls:
          if(final_response.tool_calls == [],
            do: response.tool_calls,
            else: final_response.tool_calls
          ),
        usage: merge_usage(response.usage, final_response.usage),
        raw: Map.merge(response.raw || %{}, final_response.raw || %{})
    }
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :stream_end, usage: usage},
         %Response{} = response
       ) do
    %{response | usage: merge_usage(response.usage, usage)}
  end

  defp accumulate_stream_event(
         %StreamEvent{type: :error, error: error, raw: raw},
         %Response{} = response
       ) do
    stream_errors = get_in(response.raw, ["stream_errors"]) || []
    merged_raw = Map.merge(response.raw || %{}, raw || %{})
    %{response | raw: Map.put(merged_raw, "stream_errors", stream_errors ++ [error])}
  end

  defp accumulate_stream_event(_event, %Response{} = response), do: response

  defp finalize_accumulated_response(%Response{} = response) do
    normalized_usage = normalize_usage_totals(response.usage)
    raw = response.raw || %{}

    case Map.get(raw, "stream_errors") do
      [] -> %{response | usage: normalized_usage, raw: Map.delete(raw, "stream_errors")}
      _ -> %{response | usage: normalized_usage}
    end
  end

  defp merge_usage(%Usage{} = base, %Usage{} = overlay) do
    %Usage{
      input_tokens: pick_usage_value(base.input_tokens, overlay.input_tokens),
      output_tokens: pick_usage_value(base.output_tokens, overlay.output_tokens),
      total_tokens: pick_usage_value(base.total_tokens, overlay.total_tokens),
      reasoning_tokens: pick_usage_value(base.reasoning_tokens, overlay.reasoning_tokens),
      cache_read_tokens: pick_usage_value(base.cache_read_tokens, overlay.cache_read_tokens),
      cache_write_tokens: pick_usage_value(base.cache_write_tokens, overlay.cache_write_tokens)
    }
  end

  defp merge_usage(%Usage{} = base, _overlay), do: base
  defp merge_usage(_base, %Usage{} = overlay), do: overlay
  defp merge_usage(_base, _overlay), do: %Usage{}

  defp pick_usage_value(_base, overlay) when is_integer(overlay) and overlay > 0, do: overlay
  defp pick_usage_value(base, _overlay) when is_integer(base), do: base
  defp pick_usage_value(_base, overlay) when is_integer(overlay), do: overlay
  defp pick_usage_value(_base, _overlay), do: 0

  defp normalize_usage_totals(%Usage{} = usage) do
    total =
      case usage.total_tokens do
        value when is_integer(value) and value > 0 -> value
        _ -> max(usage.input_tokens, 0) + max(usage.output_tokens, 0)
      end

    %{usage | total_tokens: total}
  end

  defp decode_json_response(%Response{text: text}) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, value} when is_map(value) or is_list(value) ->
        {:ok, value}

      {:ok, _value} ->
        {:error, :json_response_must_be_object_or_array}

      {:error, reason} ->
        {:error, {:invalid_json_response, Exception.message(reason)}}
    end
  end

  defp decode_json_response(_response), do: {:error, :empty_json_response}

  defp config_to_map(config) when is_list(config), do: Enum.into(config, %{})
  defp config_to_map(config) when is_map(config), do: config
  defp config_to_map(_config), do: %{}

  defp normalize_provider_map(providers) when is_map(providers) do
    providers
    |> Enum.reduce(%{}, fn {name, adapter}, acc ->
      case normalize_provider_entry(name, adapter) do
        nil -> acc
        {provider_name, module} -> Map.put(acc, provider_name, module)
      end
    end)
  end

  defp normalize_provider_map(_providers), do: %{}

  defp normalize_provider_entry(name, adapter) when is_atom(adapter) do
    provider_name =
      name
      |> to_string()
      |> String.trim()

    if provider_name == "", do: nil, else: {provider_name, adapter}
  end

  defp normalize_provider_entry(_name, _adapter), do: nil

  defp blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_string?(nil), do: true
  defp blank_string?(_value), do: false

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
