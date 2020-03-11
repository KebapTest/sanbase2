defmodule SanbaseWeb.Graphql.Clickhouse.AssetsHeldByAdderssApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  setup do
    p1 = insert(:random_erc20_project)
    p2 = insert(:random_erc20_project)

    eth_project = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})

    {:ok, [p1: p1, p2: p2, eth_project: eth_project]}
  end

  test "historical balances returns lists of results for ETH", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok,
          [
            %{balance: -100.0, slug: context.p1.slug},
            %{balance: 200.0, slug: context.p2.slug}
          ]}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: 1000.0, slug: context.eth_project.slug}]}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "ETH")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{
               "data" => %{
                 "assetsHeldByAddress" => [
                   %{"balance" => 1.0e3, "slug" => context.eth_project.slug},
                   %{"balance" => 200.0, "slug" => context.p2.slug}
                 ]
               }
             }
    end
  end

  test "historical balances returns lists of results for BTC", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.BtcBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: 200.0, slug: "bitcoin"}]}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "BTC")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{
               "data" => %{
                 "assetsHeldByAddress" => [
                   %{"balance" => 200.0, "slug" => "bitcoin"}
                 ]
               }
             }
    end
  end

  test "historical balances returns empty list", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ -> {:ok, []} end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ -> {:ok, []} end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "ETH")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end
  end

  test "one of the historical balances returns error", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.Erc20Balance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, []}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:error, "Something went wrong"}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "ETH")

      assert capture_log(fn ->
               result =
                 context.conn
                 |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
                 |> json_response(200)

               error = result["errors"] |> List.first()

               assert error["message"] =~
                        "Can't fetch Assets held by address for address: #{address}"
             end) =~ "Can't fetch Assets held by address for address: #{address}"
    end
  end

  test "negative balances are discarded", context do
    with_mocks [
      {Sanbase.Clickhouse.HistoricalBalance.XrpBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok,
          [
            %{balance: -100.0, slug: context.p1.slug},
            %{balance: -200.0, slug: context.p2.slug}
          ]}
       end},
      {Sanbase.Clickhouse.HistoricalBalance.EthBalance, [:passthrough],
       assets_held_by_address: fn _ ->
         {:ok, [%{balance: -500, slug: context.eth_project.slug}]}
       end}
    ] do
      address = "0x123"

      query = assets_held_by_address_query(address, "XRP")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "assetsHeldByAddress"))
        |> json_response(200)

      assert result == %{"data" => %{"assetsHeldByAddress" => []}}
    end
  end

  defp assets_held_by_address_query(address, infrastructure) do
    """
      {
        assetsHeldByAddress(
          selector: {infrastructure: "#{infrastructure}", address: "#{address}"}
        ){
            slug
            balance
        }
      }
    """
  end
end
