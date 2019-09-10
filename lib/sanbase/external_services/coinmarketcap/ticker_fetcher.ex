defmodule Sanbase.ExternalServices.Coinmarketcap.TickerFetcher do
  @moduledoc ~s"""
    A GenServer, which updates the data from coinmarketcap on a regular basis.

    Fetches only the current info and no historical data.
    On predefined intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  require Sanbase.Utils.Config, as: Config
  require Logger

  alias Sanbase.Repo
  alias Sanbase.DateTimeUtils
  alias Sanbase.Model.{LatestCoinmarketcapData, Project}
  alias Sanbase.ExternalServices.Coinmarketcap.Ticker
  alias Sanbase.Prices.Store

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()

      Process.send(self(), :sync, [:noconnect])

      update_interval = Config.get(:update_interval) |> String.to_integer()

      Logger.info(
        "[CMC] Starting TickerFetcher scraper. It will query coinmarketcap every #{
          update_interval
        } seconds."
      )

      {:ok, %{update_interval: update_interval}}
    else
      :ignore
    end
  end

  def work() do
    Logger.info("[CMC] Fetching realtime data from coinmarketcap")
    # Fetch current coinmarketcap data for many tickers
    {:ok, tickers} = Ticker.fetch_data()

    # Create a project if it's a new one in the top projects and we don't have it
    tickers
    |> Enum.take(top_projects_to_follow())
    |> Enum.each(&insert_or_update_project/1)

    # Store the data in LatestCoinmarketcapData in postgres
    tickers
    |> Enum.each(&store_latest_coinmarketcap_data!/1)

    # Store the data in Influxdb
    tickers
    |> Enum.map(&Ticker.convert_for_importing/1)
    |> Store.import()

    Logger.info(
      "[CMC] Fetching realtime data from coinmarketcap done. The data is imported in the database."
    )
  end

  # Helper functions

  def handle_info(:sync, %{update_interval: update_interval} = state) do
    work()
    Process.send_after(self(), :sync, update_interval * 1000)

    {:noreply, state}
  end

  defp store_latest_coinmarketcap_data!(%Ticker{id: coinmarketcap_id} = ticker) do
    coinmarketcap_id
    |> LatestCoinmarketcapData.get_or_build()
    |> LatestCoinmarketcapData.changeset(%{
      market_cap_usd: ticker.market_cap_usd,
      name: ticker.name,
      price_usd: ticker.price_usd,
      price_btc: ticker.price_btc,
      rank: ticker.rank,
      volume_usd: ticker."24h_volume_usd",
      available_supply: ticker.available_supply,
      total_supply: ticker.total_supply,
      symbol: ticker.symbol,
      percent_change_1h: ticker.percent_change_1h,
      percent_change_24h: ticker.percent_change_24h,
      percent_change_7d: ticker.percent_change_7d,
      update_time: DateTimeUtils.from_iso8601!(ticker.last_updated)
    })
    |> Repo.insert_or_update!()
  end

  defp insert_or_update_project(%Ticker{id: slug, name: name, symbol: ticker}) do
    case find_or_init_project(%Project{name: name, slug: slug, ticker: ticker}) do
      {:not_existing_project, changeset} ->
        # If there is not id then the project was not returned from the DB
        # but initialized by the function
        project = changeset |> Repo.insert_or_update!()

        Project.SourceSlugMapping.create(%{
          source: "coinmarketcap",
          slug: project.slug,
          project_id: project.id
        })

      {:existing_project, changeset} ->
        Repo.insert_or_update!(changeset)
    end
  end

  defp find_or_init_project(%Project{slug: slug} = project) do
    case Project.by_slug(slug) do
      nil ->
        {:not_existing_project, Project.changeset(project)}

      existing_project ->
        {:existing_project,
         Project.changeset(existing_project, %{
           slug: slug,
           ticker: project.ticker
         })}
    end
  end

  defp top_projects_to_follow() do
    Config.get(:top_projects_to_follow, "25") |> String.to_integer()
  end
end
