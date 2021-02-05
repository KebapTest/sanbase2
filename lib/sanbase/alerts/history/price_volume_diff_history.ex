defmodule Sanbase.Alert.History.PriceVolumeDifferenceHistory do
  @moduledoc """
  Implementations of historical trigger points for price_volume_difference.
  The history goes 180 days back.
  """

  alias Sanbase.Alert.Trigger.PriceVolumeDifferenceTriggerSettings

  require Logger

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          price_volume_diff: float(),
          triggered?: boolean()
        }

  defimpl Sanbase.Alert.History, for: PriceVolumeDifferenceTriggerSettings do
    @historical_days_from 180

    alias Sanbase.Alert.History.PriceVolumeDifferenceHistory

    @spec historical_trigger_points(%PriceVolumeDifferenceTriggerSettings{}, String.t()) ::
            {:ok, list(PriceVolumeDifferenceHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %PriceVolumeDifferenceTriggerSettings{target: %{slug: target}} = settings,
          cooldown
        )
        when is_binary(target) do
      case get_price_volume_data(settings) do
        {:ok, result} ->
          result = result |> add_triggered_marks(cooldown, settings)
          {:ok, result}

        {:error, error} ->
          {:error, error}
      end
    end

    defp get_price_volume_data(settings) do
      Sanbase.TechIndicators.PriceVolumeDifference.price_volume_diff(
        Sanbase.Model.Project.by_slug(settings.target.slug),
        "USD",
        Timex.shift(Timex.now(), days: -@historical_days_from),
        Timex.now(),
        settings.aggregate_interval,
        settings.window_type,
        settings.approximation_window,
        settings.comparison_window
      )
    end

    defp add_triggered_marks(result, cooldown, settings) do
      threshold = settings.threshold

      result
      |> Enum.reduce({[], DateTime.from_unix!(0)}, fn
        %{datetime: datetime, price_volume_diff: pvd} = elem, {acc, cooldown_until} ->
          # triggered if not in cooldown and the value is above the threshold
          triggered? = DateTime.compare(datetime, cooldown_until) != :lt and pvd >= threshold

          case triggered? do
            false ->
              new_elem = elem |> Map.put(:triggered?, false)
              {[new_elem | acc], cooldown_until}

            true ->
              new_elem = elem |> Map.put(:triggered?, true)

              cooldown_until =
                Timex.shift(datetime,
                  seconds: Sanbase.DateTimeUtils.str_to_sec(cooldown)
                )

              {[new_elem | acc], cooldown_until}
          end
      end)
      |> elem(0)
      |> Enum.reverse()
    end
  end
end
