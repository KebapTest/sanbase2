defmodule SanbaseWeb.Graphql.Resolvers.EtherbiResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [fit_from_datetime: 2, calibrate_interval: 7]

  import Sanbase.Utils.ErrorHandling,
    only: [handle_graphql_error: 3]

  alias Sanbase.Model.{Infrastructure, Project, ExchangeAddress}

  alias Sanbase.Blockchain.{
    TokenVelocity,
    TokenCirculation,
    TokenAgeConsumed,
    TransactionVolume,
    ExchangeFundsFlow
  }

  alias Sanbase.Clickhouse.Bitcoin

  # Return this number of datapoints is the provided interval is an empty string
  @datapoints 50

  @doc ~S"""
  Return the token age consumed for the given slug and time period.
  """
  def token_age_consumed(
        _root,
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86_400, @datapoints),
         {:ok, result} <- Bitcoin.token_age_consumed(from, to, interval) do
      result = Enum.map(result, fn elem -> Map.put(elem, :burn_rate, elem.token_age_consumed) end)
      {:ok, result}
    end
  end

  def token_age_consumed(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenAgeConsumed, contract, from, to, interval, 3600, @datapoints),
         {:ok, token_age_consumed} <-
           TokenAgeConsumed.token_age_consumed(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age_consumed |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Burn Rate", slug, error)}
    end
  end

  @doc ~S"""
  Return the average age of the tokens that were transacted for the given slug and time period.
  """
  def average_token_age_consumed_in_days(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenAgeConsumed, contract, from, to, interval, 3600, @datapoints),
         {:ok, token_age} <-
           TokenAgeConsumed.average_token_age_consumed_in_days(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_age |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Average Token Age Consumed In Days", slug, error)}
    end
  end

  @doc ~S"""
  Return the transaction volume for the given slug and time period.
  """
  def transaction_volume(
        _root,
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86_400, @datapoints) do
      Bitcoin.transaction_volume(from, to, interval)
    end
  end

  def transaction_volume(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TransactionVolume, contract, from, to, interval, 3600, @datapoints),
         {:ok, trx_volumes} <-
           TransactionVolume.transaction_volume(contract, from, to, interval, token_decimals) do
      {:ok, trx_volumes |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Transaction Volume", slug, error)}
    end
  end

  @doc ~S"""
  Return the amount of tokens that were transacted in or out of an exchange wallet for a given slug
  and time period
  """
  def exchange_funds_flow(
        _root,
        %{
          slug: slug,
          from: from,
          to: to,
          interval: interval
        } = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(ExchangeFundsFlow, contract, from, to, interval, 3600, @datapoints),
         {:ok, exchange_funds_flow} <-
           ExchangeFundsFlow.transactions_in_out_difference(
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, exchange_funds_flow |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Exchange Funds Flow", slug, error)}
    end
  end

  @doc ~s"""
  Returns the token circulation for less than a day for a given slug and time period.
  """
  def token_circulation(
        _root,
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86_400, @datapoints) do
      Bitcoin.token_circulation(from, to, interval)
    end
  end

  def token_circulation(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenCirculation, contract, from, to, interval, 86_400, @datapoints),
         {:ok, token_circulation} <-
           TokenCirculation.token_circulation(
             :less_than_a_day,
             contract,
             from,
             to,
             interval,
             token_decimals
           ) do
      {:ok, token_circulation |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Token Circulation", slug, error)}
    end
  end

  @doc ~s"""
  Returns the token velocity for a given slug and time period.
  """
  def token_velocity(
        _root,
        %{slug: "bitcoin", from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Bitcoin, "bitcoin", from, to, interval, 86_400, @datapoints) do
      Bitcoin.token_velocity(from, to, interval)
    end
  end

  def token_velocity(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    with {:ok, contract, token_decimals} <- Project.contract_info_by_slug(slug),
         {:ok, from, to, interval} <-
           calibrate_interval(TokenVelocity, contract, from, to, interval, 86_400, @datapoints),
         {:ok, token_velocity} <-
           TokenVelocity.token_velocity(contract, from, to, interval, token_decimals) do
      {:ok, token_velocity |> fit_from_datetime(args)}
    else
      {:error, error} ->
        {:error, handle_graphql_error("Token Velocity", slug, error)}
    end
  end

  def all_exchange_wallets(_root, _args, _resolution) do
    {:ok, ExchangeAddress.all_exchange_wallets()}
  end

  def exchange_wallets(_root, %{slug: "ethereum"}, _resolution) do
    {:ok, ExchangeAddress.exchange_wallets_by_infrastructure(Infrastructure.get("ETH"))}
  end

  def exchange_wallets(_root, %{slug: "bitcoin"}, _resolution) do
    {:ok, ExchangeAddress.exchange_wallets_by_infrastructure(Infrastructure.get("BTC"))}
  end

  def exchange_wallets(_, _, _) do
    {:error, "Currently only ethereum and bitcoin exchanges are supported"}
  end
end
