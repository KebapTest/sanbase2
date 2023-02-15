defmodule Sanbase.Billing.Plan.Restrictions do
  @moduledoc ~s"""
  Work with the access restrictions for all queries and metrics.
  A time restrictions is defined by the query/metric, plan and product.
  """

  alias Sanbase.Billing.Plan.AccessChecker

  @type restriction :: %{
          type: String.t(),
          name: String.t(),
          min_interval: String.t(),
          is_accessible: boolean(),
          is_restricted: boolean(),
          restricted_from: DateTime.t() | nil,
          restricted_to: DateTime.t() | nil
        }

  @type query_or_argument :: {:metric, String.t()} | {:signal, String.t()} | {:query, atom()}
  @spec get(query_or_argument, String.t(), String.t()) :: restriction()
  def get({type, name} = query_or_argument, plan_name, product_code)
      when type in [:metric, :signal, :query] do
    type_str = to_string(type)
    name_str = construct_name(type, name)

    case AccessChecker.plan_has_access?(plan_name, product_code, query_or_argument) do
      false ->
        no_access_map(type_str, name_str)

      true ->
        case AccessChecker.is_restricted?(plan_name, product_code, query_or_argument) do
          false ->
            not_restricted_access_map(type_str, name_str)

          true ->
            maybe_restricted_access_map(
              type_str,
              name_str,
              plan_name,
              product_code,
              query_or_argument
            )
        end
    end
  end

  @doc ~s"""
  Return a list in which every element describes either a metric or a query.
  The elements are maps describing the time restrictions of the given metric/query.
  """
  @spec get_all(String.t(), String.t()) :: list(restriction)
  def get_all(plan_name, product_code) do
    metrics = Sanbase.Metric.available_metrics() |> Enum.map(&{:metric, &1})
    signals = Sanbase.Signal.available_signals() |> Enum.map(&{:signal, &1})

    queries =
      Sanbase.Project.AvailableQueries.all_atom_names()
      |> Enum.map(&{:query, &1})

    # elements are {:metric, <string>} or {:query, <atom>} or {:signal, <string>}
    result =
      (queries ++ metrics ++ signals)
      |> Enum.map(fn query_or_argument -> get(query_or_argument, plan_name, product_code) end)

    (get_extra_queries(plan_name, product_code) ++ result)
    |> Enum.uniq_by(& &1.name)
    |> Enum.sort_by(& &1.name)
  end

  # Private functions

  defp no_access_map(type_str, name_str) do
    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: false,
      is_restricted: true,
      restricted_from: nil,
      restricted_to: nil
    }
  end

  defp not_restricted_access_map(type_str, name_str) do
    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: true,
      is_restricted: false
    }
  end

  defp maybe_restricted_access_map(type_str, name_str, plan_name, product_code, query_or_metric) do
    now = Timex.now()

    restricted_from =
      case AccessChecker.historical_data_in_days(plan_name, product_code, query_or_metric) do
        nil -> nil
        days -> Timex.shift(now, days: -days)
      end

    restricted_to =
      case AccessChecker.realtime_data_cut_off_in_days(plan_name, product_code, query_or_metric) do
        nil -> nil
        0 -> nil
        days -> Timex.shift(now, days: -days)
      end

    %{
      type: type_str,
      name: name_str,
      min_interval: min_interval(type_str, name_str),
      is_accessible: true,
      is_restricted: not is_nil(restricted_from) or not is_nil(restricted_to),
      restricted_from: restricted_from,
      restricted_to: restricted_to
    }
  end

  defp construct_name(:metric, name), do: name |> to_string()
  defp construct_name(:signal, name), do: name |> to_string()
  defp construct_name(:query, name), do: name |> Inflex.camelize(:lower)

  defp min_interval("metric", metric) do
    {:ok, metadata} = Sanbase.Metric.metadata(metric)
    metadata.min_interval
  end

  defp min_interval("signal", signal) do
    {:ok, metadata} = Sanbase.Signal.metadata(signal)
    metadata.min_interval
  end

  defp min_interval("query", query)
       when query in [
              "dailyActiveDeposits",
              "historyTwitterData",
              "percentOfTokenSupplyOnExchanges"
            ],
       do: "1d"

  defp min_interval("query", query)
       when query in [
              "gasUsed",
              "devActivity",
              "githubActivity",
              "historicalBalance",
              "historyPrice",
              "socialDominance",
              "githubActivity",
              "minersBalance",
              "ohlc",
              "getProjectTrendingHistory",
              "ethSpentOverTime"
            ],
       do: "5m"

  defp min_interval("query", _query), do: nil

  defp get_extra_queries(_plan_name, _product_code) do
    [not_restricted_access_map("query", "ethSpentOverTime")]
  end
end
