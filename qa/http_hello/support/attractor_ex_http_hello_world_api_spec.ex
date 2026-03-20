defmodule AttractorEx.HTTPHelloWorldApiSpec do
  @moduledoc false

  alias OpenApiSpex.{Components, Info, OpenApi, Schema}

  @behaviour OpenApi

  defmodule StatusErrorResponse do
    @moduledoc false

    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StatusErrorResponse",
      description: "Hello-world schema for the /status missing pipeline_id error payload.",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          description: "Human-readable error message for a malformed status request."
        }
      },
      required: [:error],
      example: %{"error" => "pipeline_id is required"}
    })
  end

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "AttractorEx HTTP API Hello World",
        version: "1.0.0"
      },
      paths: %{},
      components: %Components{
        schemas: %{
          StatusErrorResponse: StatusErrorResponse
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
