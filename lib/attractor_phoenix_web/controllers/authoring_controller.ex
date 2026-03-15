defmodule AttractorPhoenixWeb.AuthoringController do
  use AttractorPhoenixWeb, :controller

  alias AttractorEx.Authoring

  def analyze(conn, %{"dot" => dot}) when is_binary(dot) do
    case Authoring.analyze(dot) do
      {:ok, payload} -> json(conn, payload)
      {:error, payload} -> conn |> put_status(:unprocessable_entity) |> json(payload)
    end
  end

  def analyze(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{"error" => "dot is required"})
  end

  def templates(conn, _params) do
    json(conn, %{"templates" => Authoring.templates()})
  end

  def transform(conn, %{"action" => action} = params) when is_binary(action) do
    case Authoring.transform(action, params) do
      {:ok, payload} -> json(conn, payload)
      {:error, payload} -> conn |> put_status(:unprocessable_entity) |> json(payload)
    end
  end

  def transform(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{"error" => "action is required"})
  end
end
