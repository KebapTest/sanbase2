defmodule Sanbase.Clickhouse.HistoricalBalance.Erc20Balance do
  @moduledoc ~s"""
  Module for working with historical ERC20 balances.
  """

  @behaviour Sanbase.Clickhouse.HistoricalBalance.Behaviour
  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  alias Sanbase.ClickhouseRepo

  @table "erc20_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change erc20 balances")

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def assets_held_by_address(address) do
    {query, args} = assets_held_by_address_query(address)

    ClickhouseRepo.query_transform(query, args, fn [slug, balance] ->
      %{
        slug: slug,
        balance: balance
      }
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance([], _, _, _, _, _), do: {:ok, []}

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(addresses, contract, decimals, from, to, interval)
      when is_list(addresses) do
    combine_historical_balances(addresses, fn address ->
      historical_balance(address, contract, decimals, from, to, interval)
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def historical_balance(address, contract, decimals, from, to, interval) do
    pow_decimals = Sanbase.Math.ipow(10, decimals)
    address = String.downcase(address)
    contract = String.downcase(contract)

    {query, args} = historical_balance_query(address, contract, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, has_changed] ->
      %{
        datetime: DateTime.from_unix!(dt),
        balance: value / pow_decimals,
        has_changed: has_changed
      }
    end)
    |> maybe_update_first_balance(fn -> last_balance_before(address, contract, decimals, from) end)
    |> maybe_fill_gaps_last_seen_balance()
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def balance_change([], _, _, _, _), do: {:ok, []}

  def balance_change(address_or_addresses, contract, token_decimals, from, to) do
    token_decimals = Sanbase.Math.ipow(10, token_decimals)

    query = """
    SELECT
      address,
      argMaxIf(value, dt, dt<=?3 AND sign = 1) AS start_balance,
      argMaxIf(value, dt, dt<=?4 AND sign = 1) AS end_balance,
      end_balance - start_balance AS diff
    FROM #{@table} FINAL
    PREWHERE
      address IN (?1) AND
      assetRefId = cityHash64('ETH_' || ?2)
    GROUP BY address
    """

    addresses = address_or_addresses |> List.wrap() |> Enum.map(&String.downcase/1)
    args = [addresses, contract, from, to]

    ClickhouseRepo.query_transform(query, args, fn [address, start_balance, end_balance, change] ->
      {address,
       {start_balance / token_decimals, end_balance / token_decimals, change / token_decimals}}
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance(addresses, contract, decimals, from, to) do
    query = """
    SELECT address, argMax(value, dt)
    FROM #{@table}
    PREWHERE
      address IN (?1) AND
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt >= toDateTime(?3) AND
      dt < toDateTime(?4) AND
      sign = 1
    GROUP BY address
    """

    args = [addresses, contract, DateTime.to_unix(from), DateTime.to_unix(to)]

    decimals = Sanbase.Math.ipow(10, decimals)

    ClickhouseRepo.query_reduce(query, args, %{}, fn [address, balance], acc ->
      Map.put(acc, address, balance / decimals)
    end)
  end

  @impl Sanbase.Clickhouse.HistoricalBalance.Behaviour
  def last_balance_before(address, contract, decimals, datetime) do
    query = """
    SELECT value
    FROM #{@table}
    PREWHERE
      address = ?1 AND
      assetRefId = cityHash64('ETH_' || ?2) AND
      dt <= toDateTime(?3) AND
      sign = 1
    ORDER BY dt DESC
    LIMIT 1
    """

    args = [address, contract, DateTime.to_unix(datetime)]

    case ClickhouseRepo.query_transform(query, args, & &1) do
      {:ok, [[balance]]} -> {:ok, balance / Sanbase.Math.ipow(10, decimals)}
      {:ok, []} -> {:ok, 0}
      {:error, error} -> {:error, error}
    end
  end

  # Private functions

  defp historical_balance_query(address, contract, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - from_unix, interval) |> max(1)

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(value), toUInt8(SUM(has_changed))
      FROM (
        SELECT
          toUnixTimestamp(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toUInt8(0) AS has_changed
        FROM numbers(?2)

    UNION ALL

    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      argMax(value, dt),
      toUInt8(1) AS has_changed
    FROM #{@table}
    PREWHERE
      address = ?3 AND
      assetRefId = cityHash64('ETH_' || ?4) AND
      sign = 1 AND
      dt >= toDateTime(?5) AND
      dt < toDateTime(?6)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [interval, span, address, contract, from_unix, to_unix]

    {query, args}
  end

  defp assets_held_by_address_query(address) do
    query = """
    SELECT
      name,
      argMax(value, blockNumber) / pow(10, decimals) AS balance
    FROM erc20_balances
    INNER JOIN (
      SELECT asset_ref_id AS assetRefId, name, decimals
      FROM asset_metadata FINAL
    ) USING (assetRefId)
    PREWHERE
      address = ?1 AND
      sign = 1
    GROUP BY assetRefId, name, decimals
    """

    args = [address |> String.downcase()]

    {query, args}
  end
end
