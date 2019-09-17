defmodule SanbaseWeb.Graphql.Resolvers.ExchangeResolver do
  require Logger

  alias Sanbase.Model.{ExchangeAddress, Infrastructure}
  alias Sanbase.Clickhouse.EthTransfers

  @doc ~s"List all exchanges"
  def all_exchanges(_root, %{slug: "ethereum"}, _resolution) do
    {:ok, ExchangeAddress.exchange_names_by_infrastructure(Infrastructure.get("ETH"))}
  end

  def all_exchanges(_root, %{slug: "bitcoin"}, _resolution) do
    {:ok, ExchangeAddress.exchange_names_by_infrastructure(Infrastructure.get("BTC"))}
  end

  def all_exchanges(_, _, _) do
    {:error, "Currently only ethereum and bitcoin exchanges are supported"}
  end

  @doc ~s"""
  Return the accumulated volume of all the exchange addresses belonging to a certain exchange
  """
  def exchange_volume(_root, %{exchange: exchange, from: from, to: to}, _resolution) do
    with {:ok, addresses} <- ExchangeAddress.addresses_for_exchange(exchange),
         {:ok, exchange_volume} <- EthTransfers.exchange_volume(addresses, from, to) do
      {:ok, exchange_volume}
    else
      error ->
        Logger.error("Error getting exchange volume for: #{exchange}. #{inspect(error)}")
        {:error, "Error getting exchange volume for: #{exchange}"}
    end
  end
end
