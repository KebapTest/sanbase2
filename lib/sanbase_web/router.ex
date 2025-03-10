defmodule SanbaseWeb.Router do
  # credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
  use SanbaseWeb, :router

  pipeline :admin_pod_only do
    plug(SanbaseWeb.Plug.AdminPodOnly)
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {SanbaseWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :basic_auth do
    plug(SanbaseWeb.Plug.BasicAuth)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(RemoteIp)
    plug(:fetch_session)
    plug(SanbaseWeb.Graphql.AuthPlug)
    plug(SanbaseWeb.Graphql.ContextPlug)
    plug(SanbaseWeb.Graphql.RequestHaltPlug)
  end

  pipeline :telegram do
    plug(SanbaseWeb.Plug.TelegramMatchPlug)
  end

  pipeline :bot_login do
    plug(:fetch_session)
    plug(SanbaseWeb.Plug.BotLoginPlug)
  end

  use ExAdmin.Router
  use Kaffy.Routes, scope: "/admin3", pipe_through: [:admin_pod_only, :basic_auth]

  scope "/auth", SanbaseWeb do
    pipe_through(:browser)

    get("/delete", AuthController, :delete)
    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
  end

  scope "/admin", ExAdmin do
    pipe_through([:admin_pod_only, :browser, :basic_auth])
    admin_routes()
  end

  scope "/admin2", SanbaseWeb do
    pipe_through([:admin_pod_only, :browser, :basic_auth])
    import Phoenix.LiveDashboard.Router

    live_dashboard("/dashboard", metrics: SanbaseWeb.Telemetry, ecto_repos: [Sanbase.Repo])
    live("/monitored_twitter_handle_live", MonitoredTwitterHandleLive)

    get("/", CustomAdminController, :index)
    get("/anonymize_comment/:id", CommentModerationController, :anonymize_comment)
    get("/delete_subcomment_tree/:id", CommentModerationController, :delete_subcomment_tree)

    resources("/reports", ReportController)
    resources("/sheets_templates", SheetsTemplateController)
    resources("/webinars", WebinarController)
    resources("/custom_plans", CustomPlanController)
    post("/generic/search", GenericController, :search)
    get("/generic/show_action", GenericController, :show_action)
    resources("/generic", GenericController)
  end

  scope "/" do
    pipe_through(:api)

    forward(
      "/graphql",
      Absinthe.Plug,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 50_000,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
    )

    forward(
      "/graphiql",
      # Use own version of the plug with fixed XSS vulnerability
      SanbaseWeb.Graphql.GraphiqlPlug,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      socket: SanbaseWeb.UserSocket,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 50_000,
      interface: :simple,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
    )

    forward(
      "/graphiql_advanced",
      # Use own version of the plug with fixed XSS vulnerability
      Absinthe.Plug.GraphiQL,
      json_codec: Jason,
      schema: SanbaseWeb.Graphql.Schema,
      socket: SanbaseWeb.UserSocket,
      document_providers: [
        SanbaseWeb.Graphql.DocumentProvider,
        Absinthe.Plug.DocumentProvider.Default
      ],
      analyze_complexity: true,
      max_complexity: 50_000,
      interface: :advanced,
      log_level: :info,
      before_send: {SanbaseWeb.Graphql.AbsintheBeforeSend, :before_send}
    )
  end

  scope "/", SanbaseWeb do
    pipe_through([:telegram])

    post(
      "/telegram/:path",
      TelegramController,
      :index
    )
  end

  scope "/bot", SanbaseWeb do
    pipe_through([:bot_login])

    get(
      "/login/:path",
      BotLoginController,
      :index
    )

    get(
      "/login/:path/:user",
      BotLoginController,
      :index
    )
  end

  scope "/", SanbaseWeb do
    get("/api_metric_name_mapping", MetricNameController, :api_metric_name_mapping)
    get("/projects_data", DataController, :projects_data)
    get("/santiment_team_members/:secret", DataController, :santiment_team_members)
    get("/cryptocompare_asset_mapping", CryptocompareAssetMappingController, :data)
    post("/stripe_webhook", StripeController, :webhook)

    post("/projects_data_validator_webhook", RepoReaderController, :validator_webhook)
    post("/projects_data_reader_webhook/:secret", RepoReaderController, :reader_webhook)
  end

  scope "/", SanbaseWeb do
    pipe_through(:api)

    get("/get_routed_conn", RootController, :get_routed_conn)
  end

  get("/", SanbaseWeb.RootController, :healthcheck)
  get("/healthcheck", SanbaseWeb.RootController, :healthcheck)
end
