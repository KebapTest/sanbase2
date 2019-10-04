defmodule Sanbase.Clickhouse.Metric do
  @table "daily_metrics_v2"

  @moduledoc ~s"""
  Provide access to the v2 metrics in Clickhouse

  The metrics are stored in the '#{@table}' clickhouse table where each metric
  is defined by a `metric_id` and every project is defined by an `asset_id`.
  """

  use Ecto.Schema

  import Sanbase.Clickhouse.Metric.Helper,
    only: [slug_asset_id_map: 0, asset_id_slug_map: 0, metric_name_id_map: 0]

  alias __MODULE__.FileHandler

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @aggregations [nil, :any, :sum, :avg, :min, :max, :last, :first, :median]

  @metrics_file "available_v2_metrics.json"
  @external_resource Path.join(__DIR__, @metrics_file)

  @metrics_mapset FileHandler.metrics_mapset()
  @metrics_public_name_list FileHandler.metrics_public_name_list()
  @access_map FileHandler.access_map()
  @table_map FileHandler.table_map()
  @min_interval_map FileHandler.min_interval_map()
  @free_metrics FileHandler.metrics_with_access(:free)
  @restricted_metrics FileHandler.metrics_with_access(:restricted)
  @aggregation_map FileHandler.aggregation_map()
  @name_to_column_map FileHandler.name_to_column_map()

  case Enum.filter(@aggregation_map, fn {_, aggr} -> aggr not in @aggregations end) do
    [] ->
      :ok

    metrics ->
      require(Sanbase.Break, as: Break)

      Break.break("""
      There are metrics defined in the #{@metrics_file} that have not supported aggregation.
      These metrics are: #{inspect(metrics)}
      """)
  end

  def free_metrics(), do: @free_metrics
  def restricted_metrics(), do: @restricted_metrics
  def metric_access_map(), do: @access_map

  @type slug :: String.t()
  @type metric :: String.t()
  @type interval :: String.t()
  @type metric_result :: %{datetime: Datetime.t(), value: float()}
  @type aggregation :: nil | :any | :sum | :avg | :min | :max | :last | :first | :median

  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:asset_id, :integer)
    field(:metric_id, :integer)
    field(:value, :float)
    field(:computed_at, :utc_datetime)
  end

  @doc ~s"""
  Get a given metric for a slug and time range. The metric's aggregation
  function can be changed by the last optional parameter. The available
  aggregations are #{inspect(@aggregations -- [nil])}
  """
  @spec get(metric, slug, DateTime.t(), DateTime.t(), interval, aggregation) ::
          {:ok, list(metric_result)} | {:error, String.t()}
  def get(metric, slug, from, to, interval, aggregation \\ nil)

  def get(_metric, _slug, _from, _to, _interval, aggregation)
      when aggregation not in @aggregations do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  def get(metric, slug, from, to, interval, aggregation) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        aggregation = aggregation || Map.get(@aggregation_map, metric)
        get_metric(metric, slug, from, to, interval, aggregation)
    end
  end

  def get_aggregated(metric, slug, from, to, aggregation \\ nil)

  def get_aggregated(_metric, _slug, _from, _to, aggregation)
      when aggregation not in @aggregations do
    {:error, "The aggregation '#{inspect(aggregation)}' is not supported"}
  end

  def get_aggregated(metric, slug_or_slugs, from, to, aggregation)
      when is_binary(slug_or_slugs) or is_list(slug_or_slugs) do
    slugs = slug_or_slugs |> List.wrap()

    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        aggregation = aggregation || Map.get(@aggregation_map, metric)
        get_aggregated_metric(metric, slugs, from, to, aggregation)
    end
  end

  def metadata(metric) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        get_metadata(metric)
    end
  end

  @doc ~s"""
  Return a list of available metrics.

  If a metric has an alias only the alias is added to the list. But when a metric
  is queries, the alias **and** the original metric name is accepted. This is
  done so we do not pollute the public API with too much metric names and we
  expose only the user-friendly ones.
  """
  @spec available_metrics() :: {:ok, list(String.t())}
  def available_metrics(), do: {:ok, @metrics_public_name_list}

  @spec available_metrics!() :: list(String.t())
  def available_metrics!(), do: @metrics_public_name_list

  @spec available_slugs() :: {:ok, list(String.t())} | {:error, String.t()}
  def available_slugs(), do: get_available_slugs()

  @spec available_aggregations() :: {:ok, list(atom())}
  def available_aggregations(), do: {:ok, @aggregations}

  @spec available_aggregations!() :: list(atom())
  def available_aggregations!(), do: @aggregations

  def first_datetime(metric, slug) do
    case metric in @metrics_mapset do
      false ->
        metric_not_available_error(metric)

      true ->
        get_first_datetime(metric, slug)
    end
  end

  # Private functions

  defp get_first_datetime(metric, slug) do
    {query, args} = first_datetime_query(metric, slug)

    ClickhouseRepo.query_transform(query, args, fn [datetime] ->
      DateTime.from_unix!(datetime)
    end)
    |> case do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  defp metric_not_available_error(metric) do
    close = Enum.find(@metrics_mapset, fn m -> String.jaro_distance(metric, m) > 0.9 end)
    error_msg = "The metric '#{inspect(metric)}' is not available."

    case close do
      nil -> {:error, error_msg}
      close -> {:error, error_msg <> " Did you mean '#{close}'?"}
    end
  end

  defp get_metadata(metric) do
    min_interval = min_interval(metric)
    default_aggregation = Map.get(@aggregation_map, metric)

    {:ok,
     %{
       min_interval: min_interval,
       default_aggregation: default_aggregation
     }}
  end

  defp min_interval(metric), do: Map.get(@min_interval_map, metric)

  defp get_available_slugs() do
    {query, args} = available_slugs_query()

    ClickhouseRepo.query_transform(query, args, fn [slug] -> slug end)
  end

  defp get_metric(metric, slug, from, to, interval, aggregation) do
    {query, args} = metric_query(metric, slug, from, to, interval, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [unix, value] ->
      %{
        datetime: DateTime.from_unix!(unix),
        value: value
      }
    end)
  end

  defp get_aggregated_metric(metric, slugs, from, to, aggregation)
       when is_list(slugs) and length(slugs) > 20 do
    result =
      Enum.chunk_every(slugs, 20)
      |> Sanbase.Parallel.map(&get_aggregated_metric(metric, &1, from, to, aggregation),
        timeout: 25_000,
        max_concurrency: 8,
        ordered: false
      )
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(&elem(&1, 1))

    {:ok, result}
  end

  defp get_aggregated_metric(metric, slugs, from, to, aggregation) when is_list(slugs) do
    {:ok, asset_map} = slug_asset_id_map()
    {:ok, asset_id_map} = asset_id_slug_map()

    asset_ids = Map.take(asset_map, slugs) |> Map.values()
    {query, args} = aggregated_metric_query(metric, asset_ids, from, to, aggregation)

    ClickhouseRepo.query_transform(query, args, fn [asset_id, value] ->
      %{slug: Map.get(asset_id_map, asset_id), value: value}
    end)
  end

  defp aggregation(:last, value_column, dt_column), do: "argMax(#{value_column}, #{dt_column})"
  defp aggregation(:first, value_column, dt_column), do: "argMin(#{value_column}, #{dt_column})"
  defp aggregation(aggr, value_column, _dt_column), do: "#{aggr}(#{value_column})"

  defp metric_query(metric, slug, from, to, interval, aggregation) do
    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS t,
      #{aggregation(aggregation, "value", "t")}
    FROM(
      SELECT
        dt,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4) AND
        asset_id = (
          SELECT argMax(asset_id, computed_at)
          FROM asset_metadata
          PREWHERE name = ?5
        ) AND
        metric_id = (
          SELECT
            argMax(metric_id, computed_at) AS metric_id
          FROM
            metric_metadata
          PREWHERE
            name = ?2
        )
      GROUP BY dt
    )
    GROUP BY t
    ORDER BY t
    """

    args = [
      Sanbase.DateTimeUtils.str_to_sec(interval),
      Map.get(@name_to_column_map, metric),
      from,
      to,
      slug
    ]

    {query, args}
  end

  defp aggregated_metric_query(metric, asset_ids, from, to, aggregation) do
    query = """
    SELECT
      toUInt32(asset_id),
      #{aggregation(aggregation, "value", "t")}
    FROM(
      SELECT
        dt,
        asset_id,
        argMax(value, computed_at) AS value
      FROM #{Map.get(@table_map, metric)}
      PREWHERE
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4) AND
        asset_id IN (?1) AND
        metric_id = ?2
      GROUP BY dt, asset_id
    )
    GROUP BY asset_id
    """

    {:ok, metric_map} = metric_name_id_map()

    args = [
      asset_ids,
      Map.get(metric_map, Map.get(@name_to_column_map, metric)),
      from,
      to
    ]

    {query, args}
  end

  defp available_slugs_query() do
    query = """
    SELECT DISTINCT(name) FROM asset_metadata
    """

    args = []

    {query, args}
  end

  defp first_datetime_query(metric, nil) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      metric_id = (
        SELECT
          argMax(metric_id, computed_at) AS metric_id
        FROM
          metric_metadata
        PREWHERE
          name = ?1 ) AND
      value > 0
    """

    args = [Map.get(@name_to_column_map, metric)]

    {query, args}
  end

  defp first_datetime_query(metric, slug) do
    query = """
    SELECT
      toUnixTimestamp(toDateTime(min(dt)))
    FROM #{@table}
    PREWHERE
      asset_id = (
        SELECT argMax(asset_id, computed_at)
        FROM asset_metadata
        PREWHERE name = ?1
      ) AND metric_id = (
        SELECT
          argMax(metric_id, computed_at) AS metric_id
        FROM
          metric_metadata
        PREWHERE
          name = ?2 ) AND
      value > 0
    """

    args = [slug, Map.get(@name_to_column_map, metric)]

    {query, args}
  end
end
