defmodule Sanbase.Application.Web do
  import Sanbase.ApplicationUtils

  def init() do
    # API metrics
    SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter.install(SanbaseWeb.Graphql.Schema)
    SanbaseWeb.Graphql.Prometheus.CounterInstrumenter.install(SanbaseWeb.Graphql.Schema)
  end

  @doc ~s"""
  Return the children and options that will be started in the web container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    # Define workers and child supervisors to be supervised
    children = [
      # Start the TimescaleDB Ecto repository
      Sanbase.TimescaleRepo,

      # Start the Clickhouse Repo
      start_in({Sanbase.ClickhouseRepo, []}, [:dev, :prod]),

      # Start the Elasticsearch Cluster connection
      Sanbase.Elasticsearch.Cluster,

      # Start the graphQL in-memory cache
      {ConCache,
       [
         name: :graphql_cache,
         ttl_check_interval: :timer.seconds(30),
         global_ttl: :timer.minutes(5),
         acquire_lock_timeout: 30_000
       ]},

      # Time sereies TwitterData DB connection
      Sanbase.ExternalServices.TwitterData.Store.child_spec(),

      # Transform a list of transactions into a list of transactions
      # where addresses are marked whether or not they are an exchange address
      Sanbase.Clickhouse.MarkExchanges,

      # Start libcluster
      start_in(
        {Cluster.Supervisor,
         [
           Application.get_env(:libcluster, :topologies),
           [name: Sanbase.ClusterSupervisor]
         ]},
        [:prod]
      )
    ]

    opts = [strategy: :one_for_one, name: Sanbase.WebSupervisor, max_restarts: 5, max_seconds: 1]

    {children, opts}
  end
end
