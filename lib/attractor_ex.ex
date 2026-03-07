defmodule AttractorEx do
  @moduledoc """
  Elixir implementation of the Attractor pipeline engine.
  """

  alias AttractorEx.{Engine, Graph, HTTP, Validator}

  @spec run(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, %{diagnostics: list()}} | {:error, %{error: String.t()}}
  def run(dot, context \\ %{}, opts \\ []) when is_binary(dot) and is_map(context) do
    Engine.run(dot, context, opts)
  end

  @spec resume(String.t(), String.t() | map(), keyword()) ::
          {:ok, map()} | {:error, %{diagnostics: list()}} | {:error, %{error: String.t()}}
  def resume(dot, checkpoint_or_path, opts \\ []) when is_binary(dot) do
    Engine.resume(dot, checkpoint_or_path, opts)
  end

  @spec validate(String.t() | Graph.t(), keyword()) ::
          list() | {:error, %{error: String.t()}}
  def validate(input, opts \\ [])

  def validate(%Graph{} = graph, opts) do
    Validator.validate(graph, opts)
  end

  def validate(dot, opts) when is_binary(dot) do
    case AttractorEx.Parser.parse(dot) do
      {:ok, graph} -> Validator.validate(graph, opts)
      {:error, reason} -> {:error, %{error: reason}}
    end
  end

  @spec validate_or_raise(String.t() | Graph.t(), keyword()) :: list()
  def validate_or_raise(input, opts \\ [])

  def validate_or_raise(%Graph{} = graph, opts) do
    AttractorEx.Validator.validate_or_raise(graph, opts)
  end

  def validate_or_raise(dot, opts) when is_binary(dot) do
    case AttractorEx.Parser.parse(dot) do
      {:ok, graph} -> AttractorEx.Validator.validate_or_raise(graph, opts)
      {:error, reason} -> raise ArgumentError, "Attractor parse failed: #{reason}"
    end
  end

  @spec start_http_server(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_http_server(opts \\ []) do
    HTTP.start_server(opts)
  end

  @spec stop_http_server(pid() | atom()) :: :ok
  def stop_http_server(server) do
    HTTP.stop_server(server)
  end
end
