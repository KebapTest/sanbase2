defmodule Sanbase.Signal.History.EthWalletTriggerHistory do
  @moduledoc """
  Implementations of historical trigger points for eth_wallet signal for one year
  back and 1 day intervals.
  """

  import Sanbase.Signal.OperationEvaluation

  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance
  alias Sanbase.Signal.Trigger.EthWalletTriggerSettings

  require Logger

  @historical_days_from 365
  @historical_interval "1d"

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          balance: float(),
          triggered?: boolean()
        }

  @spec get_data(EthWalletTriggerSettings.t()) :: HistoricalBalance.historical_balance_return()
  def get_data(%{target: target, asset: asset}) do
    {from, to, interval} = get_timeseries_params()

    case addresses_from_target(target) do
      [] ->
        {:error, "No ethereum addresses provided or the target does not have ethereum addreses."}

      addresses ->
        addresses
        |> HistoricalBalance.historical_balance(asset, from, to, interval)
    end
  end

  defp addresses_from_target(%{slug: slug}) when is_binary(slug) do
    {:ok, eth_addresses} =
      slug
      |> Project.by_slug()
      |> Project.eth_addresses()

    eth_addresses
  end

  defp addresses_from_target(%{eth_address: eth_address}) when is_binary(eth_address),
    do: eth_address |> List.wrap()

  defp get_timeseries_params() do
    now = Timex.now()
    from = Timex.shift(now, days: -@historical_days_from)

    {from, now, @historical_interval}
  end

  defimpl Sanbase.Signal.History, for: EthWalletTriggerSettings do
    alias Sanbase.Signal.History.EthWalletTriggerHistory

    @spec historical_trigger_points(%EthWalletTriggerSettings{}, String.t()) ::
            {:ok, []}
            | {:ok, list(EthWalletTriggerHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %EthWalletTriggerSettings{target: %{slug: slug}} = settings,
          cooldown
        )
        when is_binary(slug) do
      do_historical_trigger_points(settings, cooldown)
    end

    def historical_trigger_points(
          %EthWalletTriggerSettings{target: %{eth_address: eth_address}} = settings,
          cooldown
        )
        when is_binary(eth_address) do
      do_historical_trigger_points(settings, cooldown)
    end

    def historical_trigger_points(%EthWalletTriggerSettings{}, _cooldown) do
      {:error, "The target can only be a single slug or a single ethereum address"}
    end

    defp do_historical_trigger_points(%EthWalletTriggerSettings{} = settings, cooldown) do
      case operation_type(settings) do
        :absolute ->
          evaluate(settings, cooldown)

        :percent ->
          {:error, "Historical trigger points for percent change are not implemented"}
      end
    end

    defp operation_type(%{operation: operation}) when is_map(operation) do
      op_name = Map.keys(operation) |> List.first()

      if op_name |> Atom.to_string() |> String.contains?("percent") do
        :percent
      else
        :absolute
      end
    end

    defp evaluate(settings, cooldown) do
      case EthWalletTriggerHistory.get_data(settings) do
        {:error, error} ->
          {:error, error}

        {:ok, []} ->
          {:ok, []}

        {:ok, data} ->
          mark_triggered(data, settings, cooldown)
      end
    end

    defp mark_triggered(data, settings, cooldown) do
      [%{balance: first_balance} | _] = data
      %{operation: operation} = settings

      cooldown_in_hours = Sanbase.DateTimeUtils.compound_duration_to_hours(cooldown)

      {acc, _, _} =
        data
        |> Enum.reduce({[], first_balance, 0}, fn
          %{balance: balance} = elem, {acc, previously_triggered_balance, 0} ->
            if operation_triggered?(balance - previously_triggered_balance, operation) do
              {
                [Map.put(elem, :triggered?, true) | acc],
                balance,
                cooldown_in_hours
              }
            else
              {
                [Map.put(elem, :triggered?, false) | acc],
                previously_triggered_balance,
                0
              }
            end

          elem, {acc, previously_triggered_balance, cooldown_left} ->
            {
              [Map.put(elem, :triggered?, false) | acc],
              previously_triggered_balance,
              cooldown_left - 1
            }
        end)

      result = acc |> Enum.reverse()
      {:ok, result}
    end
  end
end
