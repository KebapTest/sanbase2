defmodule SanbaseWeb.Graphql.Resolvers.AnomalyResolver do
  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 8]
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias Sanbase.Anomaly

  require Logger

  @datapoints 300

  def get_anomaly(_root, %{anomaly: anomaly}, _resolution) do
    case Anomaly.has_anomaly?(anomaly) do
      true -> {:ok, %{anomaly: anomaly}}
      {:error, error} -> {:error, error}
    end
  end

  def get_available_anomalies(_root, _args, _resolution), do: {:ok, Anomaly.available_anomalies()}

  def get_available_slugs(_root, _args, %{source: %{anomaly: anomaly}}),
    do: Anomaly.available_slugs(anomaly)

  def get_metadata(_root, _args, %{source: %{anomaly: anomaly}}) do
    case Anomaly.metadata(anomaly) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", anomaly, error, description: "anomaly")}
    end
  end

  def available_since(_root, %{slug: slug}, %{source: %{anomaly: anomaly}}),
    do: Anomaly.first_datetime(anomaly, slug)

  def timeseries_data(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        %{source: %{anomaly: anomaly}}
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Anomaly, anomaly, slug, from, to, interval, 86_400, @datapoints),
         {:ok, result} <-
           Anomaly.timeseries_data(anomaly, slug, from, to, interval, args[:aggregation]) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(anomaly, slug, error)}
    end
  end
end
