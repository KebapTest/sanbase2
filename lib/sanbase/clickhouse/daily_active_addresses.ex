defmodule Sanbase.Clickhouse.DailyActiveAddresses do
  @moduledoc ~s"""
  Dispatch the calculations of the daily active addresses to the correct module
  """
  use AsyncWith

  alias Sanbase.Metric
  alias Sanbase.Clickhouse.Erc20DailyActiveAddresses, as: Erc20
  alias Sanbase.Clickhouse.EthDailyActiveAddresses, as: Eth

  require Logger

  @ethereum ["ethereum", "ETH"]
  @bitcoin ["bitcoin", "BTC"]
  @async_with_timeout 25_000

  def first_datetime(slug) when slug in @ethereum do
    Eth.first_datetime(slug)
  end

  def first_datetime(slug) when slug in @bitcoin do
    Metric.first_datetime("daily_active_addresses", slug)
  end

  def first_datetime(contract) when is_binary(contract) do
    Erc20.first_datetime(contract)
  end

  def realtime_active_addresses(eth) when is_binary(eth) and eth in @ethereum do
    Eth.realtime_active_addresses()
  end

  def realtime_active_addresses(contract) do
    Erc20.realtime_active_addresses(contract)
  end

  def average_active_addresses(eth, from, to, interval)
      when is_binary(eth) and eth in @ethereum do
    Eth.average_active_addresses(from, to, interval)
  end

  def average_active_addresses(btc, from, to, interval)
      when is_binary(btc) and btc in @bitcoin do
    Metric.get("daily_active_addresses", "bitcoin", from, to, interval)
  end

  def average_active_addresses(eth, from, to, interval)
      when is_binary(eth) and eth in @ethereum do
    Eth.average_active_addresses(from, to, interval)
  end

  def average_active_addresses(contract, from, to, interval) when is_binary(contract) do
    Erc20.average_active_addresses(contract, from, to, interval)
  end

  @doc ~s"""
  Accepts a single contract(ETH or BTC in case of ethereum and bitcoin) or a list
  of contracts and returns a list tuples `{contract, active_addresses}`
  """
  @spec average_active_addresses(list(String.t()) | String.t(), DateTime.t(), DateTime.t()) ::
          {:ok, list({String.t(), number()})}
  def average_active_addresses(contracts, from, to) do
    {btc, eth, erc20} =
      contracts
      |> List.wrap()
      |> Enum.reduce({[], [], []}, fn
        c, {btc, eth, erc20} when c in @bitcoin -> {[c | btc], eth, erc20}
        c, {btc, eth, erc20} when c in @ethereum -> {btc, [c | eth], erc20}
        c, {btc, eth, erc20} when is_binary(c) -> {btc, eth, [c | erc20]}
        _, acc -> acc
      end)

    async with {:ok, btc_average_daa} <- do_btc_average_active_addresses(btc, from, to),
               {:ok, eth_average_daa} <- do_eth_average_active_addresses(eth, from, to),
               {:ok, erc20_average_daa} <- do_erc20_average_active_addresses(erc20, from, to) do
      {:ok, btc_average_daa ++ eth_average_daa ++ erc20_average_daa}
    else
      _ -> {:ok, []}
    end
  end

  # Helper functions that return lists of {slug, average_active_addresses}
  # As Ethereum and Bitcoin do not have contracts they are simulated
  # In case of error return `{:ok, []}` because the other 2 queries could succeed
  # and return meaningful results
  defp do_btc_average_active_addresses([], _, _), do: {:ok, []}

  defp do_btc_average_active_addresses([_ | _], from, to) do
    case Metric.get_aggregated("daily_active_addresses", "bitcoin", from, to) do
      {:ok, result} -> {:ok, [{"BTC", result}]}
      {:error, error} -> handle_error("Bitcoin", error)
    end
  end

  defp do_eth_average_active_addresses([], _, _), do: {:ok, []}

  defp do_eth_average_active_addresses([_ | _], from, to) do
    case Eth.average_active_addresses(from, to) do
      {:ok, result} -> {:ok, [{"ETH", result}]}
      {:error, error} -> handle_error("Ethereum", error)
    end
  end

  defp do_erc20_average_active_addresses([], _, _), do: {:ok, []}

  defp do_erc20_average_active_addresses(contracts, from, to) do
    case Erc20.average_active_addresses(contracts, from, to) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> handle_error("ERC20 contracts", error)
    end
  end

  defp handle_error(type, reason) do
    Logger.warn("Cannot fetch average active addresses for #{type}. Reason: #{inspect(reason)}")
    {:ok, []}
  end
end
