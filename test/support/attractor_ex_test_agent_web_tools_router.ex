defmodule AttractorExTest.AgentWebToolsRouter do
  @moduledoc false

  use Plug.Router

  plug :match
  plug :dispatch

  get "/search" do
    query =
      conn.query_string
      |> URI.decode_query()
      |> Map.get("q", "")

    body = """
    <html>
      <body>
        <a href="https://example.com/#{query}">#{query} result</a>
        <a href="https://example.com/secondary">Secondary result</a>
      </body>
    </html>
    """

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end

  get "/page" do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(200, "Fetched page body")
  end

  match _ do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
