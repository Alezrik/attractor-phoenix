defmodule AttractorEx.LLM.Client do
  @moduledoc false

  alias AttractorEx.LLM.Request

  defstruct providers: %{}, default_provider: nil, middleware: []

  @type t :: %__MODULE__{
          providers: %{optional(String.t()) => module()},
          default_provider: String.t() | nil,
          middleware: list((Request.t(), (Request.t() -> any()) -> any()))
        }

  def complete(%__MODULE__{} = client, %Request{} = request) do
    with {:ok, provider_name} <- resolve_provider(client, request),
         {:ok, adapter} <- fetch_adapter(client, provider_name) do
      run_with_middleware(client.middleware, request, fn req ->
        adapter.complete(%{req | provider: provider_name})
      end)
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

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
