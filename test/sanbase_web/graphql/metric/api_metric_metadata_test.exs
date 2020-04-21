defmodule SanbaseWeb.Graphql.ApiMetricMetadataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory, only: [rand_str: 0]
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Metric

  test "returns data for all available metric", %{conn: conn} do
    metrics = Metric.available_metrics()
    aggregations = Metric.available_aggregations()

    aggregations =
      aggregations |> Enum.map(fn aggr -> aggr |> Atom.to_string() |> String.upcase() end)

    for metric <- metrics do
      %{"data" => %{"getMetric" => %{"metadata" => metadata}}} = get_metric_metadata(conn, metric)
      assert metadata["metric"] == metric

      assert match?(
               %{"metric" => _, "defaultAggregation" => _, "minInterval" => _, "dataType" => _},
               metadata
             )

      assert metadata["humanReadableName"] |> is_binary()
      assert metadata["defaultAggregation"] in aggregations
      assert metadata["minInterval"] in ["1m", "5m", "6h", "1d"]
      assert metadata["dataType"] in ["TIMESERIES", "HISTOGRAM"]
      assert metadata["isRestricted"] in [true, false]

      assert is_nil(metadata["restrictedFrom"]) or
               match?(
                 %DateTime{},
                 metadata["restrictedFrom"] |> Sanbase.DateTimeUtils.from_iso8601!()
               )

      assert is_nil(metadata["restrictedTo"]) or
               match?(
                 %DateTime{},
                 metadata["restrictedTo"] |> Sanbase.DateTimeUtils.from_iso8601!()
               )
    end
  end

  test "returns error for unavailable metric", %{conn: conn} do
    rand_metrics = Enum.map(1..20, fn _ -> rand_str() end)
    rand_metrics = rand_metrics -- Metric.available_metrics()

    # Do not mock the `histogram_data` function because it's the one that rejects
    for metric <- rand_metrics do
      %{
        "errors" => [
          %{"message" => error_message}
        ]
      } = get_metric_metadata(conn, metric)

      assert error_message == "The metric '#{metric}' is not supported or is mistyped."
    end
  end

  defp get_metric_metadata(conn, metric) do
    query = """
    {
      getMetric(metric: "#{metric}"){
        metadata{
          minInterval
          defaultAggregation
          dataType
          metric
          humanReadableName
          isRestricted
          restrictedFrom
          restrictedTo
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
