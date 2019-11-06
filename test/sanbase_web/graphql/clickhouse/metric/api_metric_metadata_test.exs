defmodule SanbaseWeb.Graphql.Clickhouse.ApiMetricMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  test "returns data for all available metric", %{conn: conn} do
    metrics = Metric.available_metrics()
    aggregations = Metric.available_aggregations()

    aggregations =
      aggregations |> Enum.map(fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for metric <- metrics do
      %{"data" => %{"getMetric" => %{"metadata" => metadata}}} = fetch_metadata(conn, metric)
      assert metadata["metric"] == metric

      assert match?(
               %{"metric" => _, "defaultAggregation" => _, "minInterval" => _, "dataType" => _},
               metadata
             )

      assert metadata["defaultAggregation"] in aggregations
      assert metadata["minInterval"] in ["1m", "5m", "1d"]
      assert metadata["dataType"] in ["TIMESERIES", "HISTOGRAM"]
    end
  end

  defp fetch_metadata(conn, metric) do
    query = """
    {
      getMetric(metric: "#{metric}"){
        metadata{
          minInterval
          defaultAggregation
          dataType
          metric
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
