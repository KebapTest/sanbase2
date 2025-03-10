defmodule Sanbase.Clickhouse.MetricAdapter.HistogramMetric do
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]
  import Sanbase.Clickhouse.MetricAdapter.HistogramSqlQuery
  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]
  import Sanbase.Metric.SqlQuery.Helper, only: [asset_id_filter: 2]

  alias Sanbase.Metric
  alias Sanbase.ClickhouseRepo

  @spent_coins_cost_histograms [
    "price_histogram",
    "spent_coins_cost",
    "all_spent_coins_cost"
  ]

  @eth2_string_label_float_value_metrics [
    "eth2_staked_amount_per_label",
    "eth2_staked_address_count_per_label",
    "eth2_unlabeled_staker_inflow_sources",
    "eth2_staking_pools",
    "eth2_staking_pools_usd"
  ]

  @eth2_datetime_staking_pools_integer_valuation_list [
    "eth2_staking_pools_validators_count_over_time",
    "eth2_staking_pools_validators_count_over_time_delta"
  ]

  @eth2_string_address_string_label_float_value_metrics [
    "eth2_top_stakers"
  ]

  @eth2_metrics @eth2_string_label_float_value_metrics ++
                  @eth2_datetime_staking_pools_integer_valuation_list ++
                  @eth2_string_address_string_label_float_value_metrics

  @spec histogram_data(String.t(), map(), DateTime.t(), DateTime.t(), String.t(), number()) ::
          {:ok, list(map())} | {:error, String.t()}
  def histogram_data(metric, selector, from, to, interval, limit)

  def histogram_data("age_distribution" = metric, %{slug: slug}, from, to, interval, limit) do
    query_struct = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query_struct, fn [unix, value] ->
      range_from = unix |> DateTime.from_unix!()

      range_to =
        [range_from |> Timex.shift(seconds: str_to_sec(interval)), to]
        |> Enum.min_by(&DateTime.to_unix/1)

      %{
        range: [range_from, range_to],
        value: value
      }
    end)
  end

  def histogram_data(metric, %{slug: slug}, from, to, interval, limit)
      when metric in @spent_coins_cost_histograms do
    query_struct = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query_struct, fn [price, amount] ->
      %{
        price: Sanbase.Math.to_float(price),
        value: Sanbase.Math.to_float(amount)
      }
    end)
    |> maybe_transform_into_buckets(slug, from, to, limit)
  end

  def histogram_data(metric, %{slug: "ethereum" = slug}, from, to, interval, limit)
      when metric in @eth2_string_label_float_value_metrics do
    query_struct = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query_struct, fn [label, amount] ->
      %{
        label: label,
        value: Sanbase.Math.to_float(amount)
      }
    end)
  end

  def histogram_data(metric, %{slug: "ethereum" = slug}, from, to, interval, limit)
      when metric in @eth2_string_address_string_label_float_value_metrics do
    query_struct = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query_struct, fn [address, label, amount] ->
      %{
        address: address,
        label: label,
        value: Sanbase.Math.to_float(amount)
      }
    end)
  end

  def histogram_data(metric, %{slug: "ethereum" = slug}, from, to, interval, limit)
      when metric in @eth2_datetime_staking_pools_integer_valuation_list do
    query_struct = histogram_data_query(metric, slug, from, to, interval, limit)

    ClickhouseRepo.query_transform(query_struct, fn [timestamp, value] ->
      %{
        datetime: DateTime.from_unix!(timestamp),
        value:
          Enum.map(value, fn [pool, int] ->
            %{staking_pool: pool, valuation: int}
          end)
      }
    end)
  end

  def first_datetime(metric, selector, opts \\ [])

  def first_datetime("age_distribution", selector, _opts) do
    sql = """
    SELECT min(dt)
    FROM distribution_deltas_5min
    WHERE asset_id = (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT 1)
    """

    params = %{selector: selector}

    Sanbase.Clickhouse.Query.new(sql, params)
    |> ClickhouseRepo.query_transform(fn [timestamp] ->
      DateTime.from_unix!(timestamp)
    end)
    |> maybe_unwrap_ok_value()
  end

  def first_datetime(metric, %{slug: slug}, opts)
      when metric in @spent_coins_cost_histograms do
    with {:ok, dt1} <- Metric.first_datetime("price_usd", %{slug: slug}, opts),
         {:ok, dt2} <-
           Metric.first_datetime("age_distribution", %{slug: slug}, opts) do
      {:ok, Enum.max([dt1, dt2], DateTime)}
    end
  end

  def first_datetime(metric, _selector, _opts)
      when metric in @eth2_metrics do
    {:ok, ~U[2020-11-03 16:44:26Z]}
  end

  def last_datetime_computed_at(metric, selector, opts \\ [])

  def last_datetime_computed_at("age_distribution", selector, _opts) do
    sql = """
    SELECT max(dt)
    FROM distribution_deltas_5min
    WHERE #{asset_id_filter(selector, argument_name: "selector")}
    """

    params = %{
      selector: asset_filter_value(selector)
    }

    Sanbase.Clickhouse.Query.new(sql, params)
    |> ClickhouseRepo.query_transform(fn [timestamp] -> DateTime.from_unix!(timestamp) end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime_computed_at(metric, %{slug: slug}, opts)
      when metric in @spent_coins_cost_histograms do
    with {:ok, dt1} <-
           Metric.last_datetime_computed_at("price_usd", %{slug: slug}, opts),
         {:ok, dt2} <-
           Metric.last_datetime_computed_at(
             "age_distribution",
             %{slug: slug},
             opts
           ) do
      {:ok, Enum.min([dt1, dt2], DateTime)}
    end
  end

  def last_datetime_computed_at(metric, _selector, _opts)
      when metric in @eth2_metrics do
    sql = "SELECT toUnixTimestamp(max(dt)) FROM eth2_staking_transfers_v2"
    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

    ClickhouseRepo.query_transform(query_struct, fn [timestamp] ->
      DateTime.from_unix!(timestamp)
    end)
    |> maybe_unwrap_ok_value()
  end

  def available_slugs("age_distribution") do
    Sanbase.Clickhouse.MetricAdapter.available_slugs("age_distribution")
  end

  def available_slugs(metric) when metric in @spent_coins_cost_histograms do
    Metric.available_slugs("price_usd")
  end

  def available_slugs(metric) when metric in @eth2_metrics do
    {:ok, ["ethereum"]}
  end

  # Aggregate the separate prices into `buckets_count` number of evenly spaced buckets
  defp maybe_transform_into_buckets({:ok, []}, _slug, _from, _to, _buckets_count),
    do: {:ok, []}

  defp maybe_transform_into_buckets({:ok, data}, slug, from, to, buckets_count) do
    # The bucket containing the avg price will get split in two
    price_break = get_price_break_point(slug, from, to)

    {min, max} = get_min_max_prices(data)

    # `buckets_count - 1` because one of the buckets will be split into 2
    bucket_size = Enum.max([Float.round((max - min) / (buckets_count - 1), 2), 0.01])

    ranges_map = ranges_map(min, buckets_count, bucket_size)

    # Put every amount moved at a given price in the proper bucket
    bucketed_data = do_transform_to_buckets(data, ranges_map, min, bucket_size, price_break)

    {:ok, bucketed_data}
  end

  defp maybe_transform_into_buckets({:error, error}, _slug, _from, _to, _limit),
    do: {:error, error}

  defp do_transform_to_buckets(prices_list, ranges_map, min, bucket_size, price_break) do
    price_break_range = price_to_range(price_break, min, bucket_size)

    Enum.reduce(prices_list, ranges_map, fn %{price: price, value: value}, acc ->
      key = price_to_range(price, min, bucket_size)

      Map.update(acc, key, 0.0, fn curr_amount ->
        Float.round(curr_amount + value, 2)
      end)
    end)
    |> split_bucket_containing_price(
      prices_list,
      price_break_range,
      price_break
    )
    |> Enum.map(fn {range, amount} -> %{range: range, value: amount} end)
    |> Enum.sort_by(fn %{range: [range_start | _]} -> range_start end)
  end

  defp get_price_break_point(slug, from, to) do
    # Get the average price for the queried. time range. It will break the [X,Y]
    # price interval containing that price into [X, price_break] and [price_break, Y]
    {:ok, %{^slug => price_break}} =
      Metric.aggregated_timeseries_data("price_usd", %{slug: slug}, from, to, aggregation: :avg)

    # The bucket that contains the average price will be the one that gets split into two.
    price_break = Sanbase.Math.round_float(price_break)

    price_break
  end

  defp get_min_max_prices(prices_list) do
    # Avoid precision issues when using `round` for prices.
    {min, max} = Enum.map(prices_list, & &1.price) |> Sanbase.Math.min_max()
    {min, max} = {Float.floor(min, 2), Float.ceil(max, 2)}

    {min, max}
  end

  defp low_high_range(low, high) do
    # Generate the range for given low and high price
    [Float.round(low, 2), Float.round(high, 2)]
  end

  defp ranges_map(min, buckets_count, bucket_size) do
    # Generate ranges tuples in the format needed by Stream.unfold/2
    price_ranges = fn value ->
      [lower, upper] = low_high_range(value, value + bucket_size)
      {[lower, upper], upper}
    end

    Stream.unfold(min, price_ranges)
    |> Enum.take(buckets_count)
    |> Enum.into(%{}, fn range -> {range, 0.0} end)
  end

  def price_to_range(price, min, bucket_size) do
    # Map the price to the proper [low, high] range
    bucket = floor((price - min) / bucket_size)
    lower = min + bucket * bucket_size
    upper = min + (1 + bucket) * bucket_size

    low_high_range(lower, upper)
  end

  # Break a bucket with range [low, high] into 2 buckes [low, divider] and [divider, high]
  # putting the proper number of entities that fall into each of the 2 ranges
  defp split_bucket_containing_price(
         bucketed_data,
         original_data,
         [low, high],
         divider
       ) do
    {lower_half_amount, upper_half_amount} =
      original_data
      |> Enum.reduce({0.0, 0.0}, fn %{price: price, value: value}, {acc_lower, acc_upper} ->
        cond do
          price >= low and price < divider -> {acc_lower + value, acc_upper}
          price >= divider and price < high -> {acc_lower, acc_upper + value}
          true -> {acc_lower, acc_upper}
        end
      end)

    bucketed_data
    |> Map.delete([low, high])
    |> Map.put([low, divider], Float.round(lower_half_amount, 2))
    |> Map.put([divider, high], Float.round(upper_half_amount, 2))
  end

  defp asset_filter_value(%{slug: slug_or_slugs}), do: slug_or_slugs
  defp asset_filter_value(_), do: nil
end
