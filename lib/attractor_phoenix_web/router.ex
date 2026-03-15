defmodule AttractorPhoenixWeb.Router do
  use AttractorPhoenixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AttractorPhoenixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AttractorPhoenixWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/runs/:id", RunLive
    live "/runs/:id/debugger", DebuggerLive
    live "/benchmark", BenchmarkLive
    live "/builder", PipelineBuilderLive
    live "/create", PipelineBuilderLive, :create
    live "/setup", SetupLive
    live "/library", PipelineLibraryLive, :index
    live "/library/new", PipelineLibraryLive, :new
    live "/library/:id/edit", PipelineLibraryLive, :edit
  end

  scope "/api", AttractorPhoenixWeb do
    pipe_through :api

    get "/authoring/templates", AuthoringController, :templates
    post "/authoring/analyze", AuthoringController, :analyze
    post "/authoring/transform", AuthoringController, :transform
  end

  # Other scopes may use custom stacks.
  # scope "/api", AttractorPhoenixWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:attractor_phoenix, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AttractorPhoenixWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
