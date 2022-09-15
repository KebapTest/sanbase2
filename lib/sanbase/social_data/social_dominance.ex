defmodule Sanbase.SocialData.SocialDominance do
  import Sanbase.Utils.ErrorHandling

  require Sanbase.Utils.Config, as: Config
  require SanbaseWeb.Graphql.Schema
  require Mockery.Macro

  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.SocialData

  @recv_timeout 15_000
  @hours_back_ensure_has_data 3
  @trending_words_size 10

  def social_dominance(selector, from, to, interval, source)
      when source in [:all, "all", :total, "total"] do
    social_dominance(selector, from, to, interval, SocialHelper.sources_total_string())
  end

  def social_dominance(%{text: text}, from, to, interval, source) do
    with {:ok, text_volume} <-
           Sanbase.SocialData.social_volume(%{text: text}, from, to, interval, source),
         {:ok, total_volume} <-
           Sanbase.SocialData.social_volume(%{text: "*"}, from, to, interval, source) do
      # If `text_volume` is empty replace it with 0 mentions, so the end result
      # will be with all dominance = 0
      text_volume_map =
        text_volume |> Enum.into(%{}, fn elem -> {elem.datetime, elem.mentions_count} end)

      result =
        Enum.map(total_volume, fn %{datetime: datetime, mentions_count: total_mentions} ->
          text_mentions = Map.get(text_volume_map, datetime, 0)
          dominance = Sanbase.Math.percent_of(text_mentions, total_mentions) || 0.0

          %{
            datetime: datetime,
            dominance: dominance |> Sanbase.Math.round_float()
          }
        end)
        |> Enum.sort_by(&DateTime.to_unix(&1.datetime))

      {:ok, result}
    end
  end

  def social_dominance(%{slug: slug}, from, to, interval, source) do
    social_dominance_request(%{slug: slug}, from, to, interval, source)
    |> case do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, result} = Jason.decode(body)
        social_dominance_result(result)

      {:ok, %{status_code: status}} ->
        warn_result(
          "Error status #{status} fetching social dominance for project with slug #{inspect(slug)}}"
        )

      {:error, %HTTPoison.Error{} = error} ->
        error_result(
          "Cannot fetch social dominance data for project with slug #{inspect(slug)}}: #{HTTPoison.Error.message(error)}"
        )
    end
  end

  def social_dominance_words(words) do
    to = Timex.now()
    from = Timex.shift(to, hours: -@hours_back_ensure_has_data)
    interval = "1h"
    source = :total

    with {:ok, words_volume} <-
           SocialData.social_volume(%{words: words}, from, to, interval, source),
         {:ok, total_volume} <- SocialData.social_volume(%{text: "*"}, from, to, interval, source) do
      words_volume_map =
        words_volume
        |> Enum.into(%{}, fn w -> {w.word, List.last(w.timeseries_data).mentions_count} end)

      total_mentions = List.last(total_volume).mentions_count

      words_dominance_map =
        words_volume_map
        |> Enum.map(fn {word, mentions} ->
          %{
            word: word,
            social_dominance: Sanbase.Math.percent_of(mentions, total_mentions) || 0.0
          }
        end)
    else
      {:ok, []} -> {:ok, nil}
      error -> {:ok, nil}
    end
  end

  def social_dominance_trending_words() do
    to = Timex.now()
    from = Timex.shift(to, hours: -@hours_back_ensure_has_data)
    interval = "1h"
    source = :total

    with {:ok, trending_words} when length(trending_words) > 0 <-
           SocialData.TrendingWords.get_currently_trending_words(@trending_words_size),
         words <- Enum.map(trending_words, & &1.word),
         {:ok, words_volume} <-
           SocialData.social_volume(%{words: words}, from, to, interval, source),
         {:ok, total_volume} <- SocialData.social_volume(%{text: "*"}, from, to, interval, source) do
      words_mentions_sum =
        Enum.map(words_volume, &List.last(&1.timeseries_data).mentions_count)
        |> Enum.sum()

      total_mentions = List.last(total_volume).mentions_count

      dominance = Sanbase.Math.percent_of(words_mentions_sum, total_mentions) || 0.0

      {:ok, dominance}
    else
      {:ok, []} -> {:ok, nil}
      error -> {:ok, nil}
    end
  end

  defp social_dominance_request(%{slug: slug}, from, to, interval, source) do
    url = "#{metrics_hub_url()}/social_dominance"

    options = [
      recv_timeout: @recv_timeout,
      params: [
        {"slug", slug},
        {"from_timestamp", from |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"to_timestamp", to |> DateTime.truncate(:second) |> DateTime.to_iso8601()},
        {"interval", interval},
        {"source", source}
      ]
    ]

    http_client().get(url, [], options)
  end

  defp social_dominance_result(%{"data" => map}) do
    result =
      Enum.map(map, fn {datetime, value} ->
        %{
          datetime: Sanbase.DateTimeUtils.from_iso8601!(datetime),
          dominance: value
        }
      end)
      |> Enum.sort_by(& &1.datetime, {:asc, DateTime})

    {:ok, result}
  end

  defp metrics_hub_url() do
    Config.module_get(Sanbase.SocialData, :metricshub_url)
  end

  defp http_client, do: Mockery.Macro.mockable(HTTPoison)
end
