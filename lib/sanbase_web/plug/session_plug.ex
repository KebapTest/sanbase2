defmodule SanbaseWeb.Plug.SessionPlug do
  @moduledoc ~s"""
  Wraps `Plug.Sesson` plug so it can be configured with runtime opts.
  """

  @behaviour Plug

  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(conn, opts) do
    runtime_opts =
      opts
      |> Keyword.put(:domain, domain())
      |> Keyword.put(:key, session_key())
      |> Plug.Session.init()

    Plug.Session.call(conn, runtime_opts)
  end

  defp domain(), do: Config.get(:domain)
  defp session_key(), do: Config.get(:session_key)
end
