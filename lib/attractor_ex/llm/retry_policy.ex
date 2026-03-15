defmodule AttractorEx.LLM.RetryPolicy do
  @moduledoc """
  Configures client-side retry behavior for adapter failures.

  Retries are only attempted for normalized `AttractorEx.LLM.Error` values marked as
  retryable, or when a custom `retry_if` callback explicitly opts in.
  """

  alias AttractorEx.LLM.Error

  defstruct max_attempts: 1,
            base_delay_ms: 200,
            max_delay_ms: 2_000,
            jitter_ratio: 0.1,
            retry_if: nil

  @type retry_if :: (Error.t(), pos_integer() -> boolean())

  @type t :: %__MODULE__{
          max_attempts: pos_integer(),
          base_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          jitter_ratio: float(),
          retry_if: retry_if() | nil
        }

  @spec new(keyword() | map() | nil) :: t() | nil
  def new(nil), do: nil
  def new(%__MODULE__{} = policy), do: policy

  def new(opts) when is_list(opts) do
    opts |> Enum.into(%{}) |> new()
  end

  def new(opts) when is_map(opts) do
    %__MODULE__{
      max_attempts:
        positive_integer(Map.get(opts, :max_attempts) || Map.get(opts, "max_attempts"), 1),
      base_delay_ms:
        non_negative_integer(Map.get(opts, :base_delay_ms) || Map.get(opts, "base_delay_ms"), 200),
      max_delay_ms:
        non_negative_integer(Map.get(opts, :max_delay_ms) || Map.get(opts, "max_delay_ms"), 2_000),
      jitter_ratio:
        normalize_jitter(Map.get(opts, :jitter_ratio) || Map.get(opts, "jitter_ratio"), 0.1),
      retry_if: Map.get(opts, :retry_if) || Map.get(opts, "retry_if")
    }
  end

  def new(_other), do: %__MODULE__{}

  @spec enabled?(t() | nil) :: boolean()
  def enabled?(%__MODULE__{max_attempts: attempts}) when attempts > 1, do: true
  def enabled?(_policy), do: false

  @spec retry?(t(), Error.t(), pos_integer()) :: boolean()
  def retry?(%__MODULE__{} = policy, %Error{} = error, attempt) do
    under_attempt_limit? = attempt < policy.max_attempts

    retryable? =
      cond do
        is_function(policy.retry_if, 2) -> policy.retry_if.(error, attempt)
        true -> Error.retryable?(error)
      end

    under_attempt_limit? and retryable?
  end

  @spec delay_ms(t(), Error.t(), pos_integer()) :: non_neg_integer()
  def delay_ms(%__MODULE__{} = policy, %Error{} = error, attempt) do
    retry_after_ms = error.retry_after_ms || 0
    backoff_ms = exponential_backoff(policy.base_delay_ms, policy.max_delay_ms, attempt)
    apply_jitter(max(retry_after_ms, backoff_ms), policy.jitter_ratio)
  end

  defp exponential_backoff(base_delay_ms, max_delay_ms, attempt) do
    multiplier = :math.pow(2, max(attempt - 1, 0)) |> round()
    min(base_delay_ms * multiplier, max_delay_ms)
  end

  defp apply_jitter(delay_ms, jitter_ratio) when delay_ms > 0 and jitter_ratio > 0 do
    jitter_window = round(delay_ms * jitter_ratio)

    if jitter_window <= 0 do
      delay_ms
    else
      lower = max(delay_ms - jitter_window, 0)
      upper = delay_ms + jitter_window
      :rand.uniform(upper - lower + 1) + lower - 1
    end
  end

  defp apply_jitter(delay_ms, _jitter_ratio), do: delay_ms

  defp positive_integer(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, fallback), do: fallback

  defp non_negative_integer(value, _fallback) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, fallback), do: fallback

  defp normalize_jitter(value, _fallback) when is_float(value) and value >= 0, do: value
  defp normalize_jitter(value, _fallback) when is_integer(value) and value >= 0, do: value / 1
  defp normalize_jitter(_value, fallback), do: fallback
end
