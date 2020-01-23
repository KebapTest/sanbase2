defmodule SanbaseWeb.Graphql.Schema.MetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.Middlewares.TransformResolution

  object :metric_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_metric, :metric do
      meta(access: :free)
      arg(:metric, non_null(:string))

      middleware(TransformResolution)
      resolve(&MetricResolver.get_metric/3)
    end

    field :get_available_metrics, list_of(:string) do
      meta(access: :free)
      cache_resolve(&MetricResolver.get_available_metrics/3, ttl: 600)
    end
  end
end
