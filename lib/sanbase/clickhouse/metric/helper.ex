defmodule Sanbase.Clickhouse.Metric.Helper do
  @moduledoc ~s"""
  Provides some helper functions for filtering the clickhouse v2 metrics
  """
  alias Sanbase.Clickhouse.Metric

  def slug_asset_id_map() do
    %{
      "santiment" => 2095,
      "maker" => 1909
    }
  end

  def asset_id_slug_map() do
    %{
      2095 => "santiment",
      1909 => "maker"
    }
  end

  def metric_name_id_map() do
    %{
      "transaction_volume" => 2
    }
  end

  def metric_with_name_containing(str) do
    {:ok, metrics} = Metric.available_metrics()
    Enum.filter(metrics, fn metric -> String.contains?(metric, str) end)
  end

  def mvrv_metrics(), do: metric_with_name_containing("mvrv") |> wrap()
  def realized_value_metrics(), do: metric_with_name_containing("realized") |> wrap()
  def token_age_consumed_metrics(), do: metric_with_name_containing("age_consumed") |> wrap()

  defp wrap(list) do
    list
    |> Enum.map(fn mvrv ->
      {:clickhouse_v2_metric, String.to_atom(mvrv)}
    end)
  end
end
