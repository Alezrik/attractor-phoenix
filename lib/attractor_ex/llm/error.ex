defmodule AttractorEx.LLM.Error do
  @moduledoc """
  Typed error returned by unified LLM adapters and client retries.

  The struct normalizes provider/API/transport failures into a consistent shape so
  callers can make retry, logging, and host-event decisions without pattern matching
  on provider-specific payloads.
  """

  defexception type: :unknown,
               message: "LLM request failed",
               provider: nil,
               status: nil,
               code: nil,
               retryable: false,
               retry_after_ms: nil,
               details: %{},
               raw: nil

  @type error_type ::
          :transport
          | :timeout
          | :rate_limited
          | :authentication
          | :permission
          | :invalid_request
          | :server
          | :api
          | :unsupported
          | :unknown

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          provider: String.t() | nil,
          status: pos_integer() | nil,
          code: String.t() | nil,
          retryable: boolean(),
          retry_after_ms: non_neg_integer() | nil,
          details: map(),
          raw: term()
        }

  @spec new(keyword()) :: t()
  def new(attrs \\ []) do
    struct!(__MODULE__, attrs)
  end

  @spec retryable?(term()) :: boolean()
  def retryable?(%__MODULE__{retryable: value}), do: value
  def retryable?(_other), do: false

  @spec normalize(term(), keyword()) :: t()
  def normalize(%__MODULE__{} = error, opts) do
    overlay =
      opts
      |> Enum.into(%{})
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    struct(error, overlay)
  end

  def normalize({:error, reason}, opts), do: normalize(reason, opts)

  def normalize({type, message}, opts) when type in [:timeout, :transport, :unsupported] do
    provider = Keyword.get(opts, :provider)

    %__MODULE__{
      type: type,
      provider: provider,
      message: normalize_message(message, default_message(type, provider)),
      retryable: type in [:timeout, :transport]
    }
  end

  def normalize(reason, opts) when is_binary(reason) do
    provider = Keyword.get(opts, :provider)

    %__MODULE__{
      type: :api,
      provider: provider,
      message: reason,
      retryable: false,
      raw: reason
    }
  end

  def normalize(reason, opts) do
    provider = Keyword.get(opts, :provider)

    %__MODULE__{
      type: :unknown,
      provider: provider,
      message: normalize_message(reason, default_message(:unknown, provider)),
      retryable: false,
      raw: reason
    }
  end

  @spec from_http_response(String.t() | nil, pos_integer(), term(), map()) :: t()
  def from_http_response(provider, status, body, headers \\ %{}) do
    error_body = extract_error_body(body)
    code = extract_error_code(error_body)
    message = extract_error_message(error_body, status)
    retry_after_ms = parse_retry_after_ms(headers)
    type = http_error_type(status)

    %__MODULE__{
      type: type,
      provider: provider,
      status: status,
      code: normalize_code(code),
      message: normalize_message(message, default_message(type, provider)),
      retryable: retryable_status?(status),
      retry_after_ms: retry_after_ms,
      details: normalize_error_details(error_body),
      raw: body
    }
  end

  defp extract_error_body(body) when is_map(body) do
    case body["error"] do
      error when is_map(error) -> error
      _ -> body
    end
  end

  defp extract_error_body(body), do: %{"message" => inspect(body)}

  defp extract_error_code(error_body) do
    error_body["code"] ||
      error_body[:code] ||
      error_body["type"] ||
      error_body[:type]
  end

  defp extract_error_message(error_body, status) do
    error_body["message"] ||
      error_body[:message] ||
      "HTTP #{status}"
  end

  defp http_error_type(408), do: :timeout
  defp http_error_type(401), do: :authentication
  defp http_error_type(403), do: :permission
  defp http_error_type(404), do: :invalid_request
  defp http_error_type(409), do: :api
  defp http_error_type(422), do: :invalid_request
  defp http_error_type(429), do: :rate_limited
  defp http_error_type(status) when status >= 500, do: :server
  defp http_error_type(_status), do: :api

  @spec transport(String.t() | nil, term()) :: t()
  def transport(provider, reason) do
    type = if timeout_reason?(reason), do: :timeout, else: :transport

    %__MODULE__{
      type: type,
      provider: provider,
      message: normalize_message(reason, default_message(type, provider)),
      retryable: true,
      raw: reason
    }
  end

  defp parse_retry_after_ms(headers) when is_map(headers) do
    headers
    |> find_header("retry-after")
    |> case do
      nil -> nil
      value -> parse_retry_after_value(value)
    end
  end

  defp parse_retry_after_ms(_headers), do: nil

  defp find_header(headers, target) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == target, do: value, else: nil

      _ ->
        nil
    end)
  end

  defp parse_retry_after_value(value) when is_list(value) do
    value |> List.first() |> parse_retry_after_value()
  end

  defp parse_retry_after_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {seconds, ""} when seconds >= 0 -> seconds * 1_000
      _ -> nil
    end
  end

  defp parse_retry_after_value(_value), do: nil

  defp retryable_status?(status), do: status in [408, 409, 425, 429] or status >= 500

  defp timeout_reason?(reason) do
    value = inspect(reason)
    String.contains?(String.downcase(value), "timeout")
  end

  defp normalize_message(message, fallback) when is_binary(message) do
    trimmed = String.trim(message)
    if trimmed == "", do: fallback, else: trimmed
  end

  defp normalize_message(message, fallback) do
    case inspect(message) do
      "" -> fallback
      value -> value
    end
  end

  defp normalize_code(nil), do: nil
  defp normalize_code(code), do: code |> to_string() |> String.trim() |> blank_to_nil()

  defp normalize_error_details(error_body) when is_map(error_body) do
    error_body
    |> Enum.reject(fn {key, _value} ->
      key in ["message", :message, "type", :type, "code", :code]
    end)
    |> Map.new()
  end

  defp default_message(type, provider) do
    label =
      provider
      |> case do
        value when is_binary(value) and value != "" -> "#{value} "
        _ -> ""
      end

    case type do
      :transport -> "#{label}transport error"
      :timeout -> "#{label}request timed out"
      :rate_limited -> "#{label}rate limited"
      :authentication -> "#{label}authentication failed"
      :permission -> "#{label}permission denied"
      :invalid_request -> "#{label}request rejected"
      :server -> "#{label}provider server error"
      :unsupported -> "#{label}operation not supported"
      :api -> "#{label}provider API error"
      :unknown -> "#{label}request failed"
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
