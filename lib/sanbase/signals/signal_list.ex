defmodule Sanbase.Signal.List do
  alias Sanbase.Signal.Trigger

  def get() do
    [
      Trigger.EthWalletTriggerSettings,
      Trigger.MetricTriggerSettings,
      Trigger.PriceVolumeDifferenceTriggerSettings,
      Trigger.ScreenerTriggerSettings,
      Trigger.TrendingWordsTriggerSettings,
      Trigger.WalletTriggerSettings
    ]
  end
end
