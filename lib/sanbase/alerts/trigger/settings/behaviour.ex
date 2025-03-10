defmodule Sanbase.Alert.Trigger.Settings.Behaviour do
  alias Sanbase.Alert.Trigger
  @type type :: String.t()

  @callback type() :: type()
  @callback post_create_process(Trigger.t()) :: :nochange | Trigger.t()
  @callback post_update_process(Trigger.t()) :: :nochange | Trigger.t()
end
