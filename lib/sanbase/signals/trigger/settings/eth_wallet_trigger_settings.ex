defmodule Sanbase.Signal.Trigger.EthWalletTriggerSettings do
  @moduledoc ~s"""
  The EthWallet signal is triggered when the balance of a wallet or set of wallets
  changes by a predefined amount for a specified asset (Ethereum, SAN tokens, etc.)

  The signal can follow a single ethereum address, a list of ethereum addresses
  or a project. When a list of addresses or a project is followed, all the addresses
  are considered to be owned by a single entity and the transfers between them
  are excluded.
  """

  use Vex.Struct

  import Sanbase.Validation
  import Sanbase.Signal.Validation
  import Sanbase.Signal.OperationEvaluation
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.HistoricalBalance
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "eth_wallet"

  @enforce_keys [:type, :channel, :target, :asset]
  defstruct type: @trigger_type,
            channel: nil,
            target: nil,
            asset: nil,
            operation: nil,
            time_window: "1d",
            filtered_target: %{list: []},
            payload: %{},
            triggered?: false

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          channel: Type.channel(),
          target: Type.complex_target(),
          asset: Type.asset(),
          operation: Type.operation(),
          time_window: Type.time_window(),
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  validates(:channel, &valid_notification_channel?/1)
  validates(:target, &valid_eth_wallet_target?/1)
  validates(:asset, &valid_slug?/1)
  validates(:operation, &valid_absolute_change_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def get_data(
        %__MODULE__{
          filtered_target: %{list: target_list, type: :eth_address}
        } = settings
      ) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(settings.time_window))

    target_list
    |> Enum.map(fn addr ->
      case balance_change(addr, settings.asset.slug, from, to) do
        [{^addr, {_, _, balance_change}}] ->
          {:eth_address, addr, balance_change, from}

        _ ->
          {:eth_address, addr, 0, from}
      end
    end)
  end

  def get_data(%__MODULE__{filtered_target: %{list: target_list, type: :slug}} = settings) do
    to = Timex.now()
    from = Timex.shift(to, seconds: -str_to_sec(settings.time_window))

    target_list
    |> Project.by_slug()
    |> Enum.map(fn %Project{} = project ->
      {:ok, eth_addresses} = Project.eth_addresses(project)

      project_balance_change =
        eth_addresses
        |> Enum.map(&String.downcase/1)
        |> balance_change(settings.asset.slug, from, to)
        |> Enum.map(fn {_, {_, _, change}} -> change end)
        |> Enum.sum()

      {:project, project, project_balance_change, from}
    end)
  end

  defp balance_change(addresses, slug, from, to) do
    cache_key =
      ["balance_change", addresses, slug, bucket_datetime(from), bucket_datetime(to)]
      |> :erlang.phash2()

    Cache.get_or_store(
      cache_key,
      fn ->
        HistoricalBalance.balance_change(
          %{infrastructure: "ETH", slug: slug},
          addresses,
          from,
          to
        )
        |> case do
          {:ok, result} -> result
          _ -> []
        end
      end
    )
  end

  # All datetimes in 5 minute time intervals will generate the same result
  # to be used in cache keys
  defp bucket_datetime(%DateTime{} = dt), do: div(DateTime.to_unix(dt, :second), 300)

  alias __MODULE__

  defimpl Sanbase.Signal.Settings, for: EthWalletTriggerSettings do
    def triggered?(%EthWalletTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%EthWalletTriggerSettings{} = settings, _trigger) do
      case EthWalletTriggerSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %EthWalletTriggerSettings{
            settings
            | triggered?: false
          }
      end
    end

    # The result heavily depends on `last_triggered`, so just the settings are not enough
    def cache_key(%EthWalletTriggerSettings{}), do: :nocache

    defp build_result(list, settings) do
      payload =
        Enum.reduce(list, %{}, fn
          {_, _, balance_change, _} = elem, payload ->
            if operation_triggered?(balance_change, settings.operation) do
              case elem do
                {:project, %Project{slug: slug} = project, balance_change, from} ->
                  Map.put(payload, slug, payload(project, settings, balance_change, from))

                {:eth_address, address, balance_change, from} ->
                  Map.put(payload, address, payload(address, settings, balance_change, from))
              end
            else
              payload
            end
        end)

      %EthWalletTriggerSettings{
        settings
        | payload: payload,
          triggered?: payload != %{}
      }
    end

    defp operation_text(value, %{amount_up: _}), do: "has increased by #{value}"
    defp operation_text(value, %{amount_down: _}), do: "has decreased by #{abs(value)}"

    defp payload(
           %Project{name: name} = project,
           settings,
           balance_change,
           from
         ) do
      """
      The #{settings.asset.slug} balance of #{name} wallets #{
        operation_text(balance_change, settings.operation)
      } since #{DateTime.truncate(from, :second)}

      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      """
    end

    defp payload(address, settings, balance_change, from) do
      """
      The #{settings.asset.slug} balance of the address #{address} #{
        operation_text(balance_change, settings.operation)
      } since #{DateTime.truncate(from, :second)}

      See the historical balance change of the address here:
      #{SanbaseWeb.Endpoint.historical_balance_url(address, settings.asset.slug)}
      """
    end
  end
end
