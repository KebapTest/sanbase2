defmodule Sanbase.Etherbi.ExchangeWalletsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    [
      conn: setup_basic_auth(build_conn(), "user", "pass")
    ]
  end

  test "returning an error when there is no basic auth" do
    query = """
    {
      exchangeWallets{
        address,
        name
      }
    }
    """

    result =
      build_conn()
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    error = json_response(result, 200)["errors"] |> hd

    assert error["message"] == "unauthorized"
  end

  test "returning an empty list of wallets if there are none in the DB", context do
    query = """
    {
      exchangeWallets{
        address,
        name
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    exchange_wallets = json_response(result, 200)["data"]["exchangeWallets"]

    assert exchange_wallets == []
  end

  test "returning a list of wallets from the DB", context do
    infr = insert(:infrastructure, %{code: "ETH"})

    insert(:exchange_address, %{address: "0x12345", name: "Binance", infrastructure_id: infr.id})
    insert(:exchange_address, %{address: "0x54321", name: "Kraken", infrastructure_id: infr.id})

    query = """
    {
      exchangeWallets{
        address
        name
        infrastructure{
          code
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "exchangeWallets"))

    exchange_wallets = json_response(result, 200)["data"]["exchangeWallets"]

    assert %{"name" => "Binance", "address" => "0x12345", "infrastructure" => %{"code" => "ETH"}} in exchange_wallets

    assert %{"name" => "Kraken", "address" => "0x54321", "infrastructure" => %{"code" => "ETH"}} in exchange_wallets
  end

  test "returning a list of all wallets from the DB", context do
    infr_eth = insert(:infrastructure, %{code: "ETH"})
    infr_xrp = insert(:infrastructure, %{code: "XRP"})

    insert(:exchange_address, %{
      address: "0x12345",
      name: "Binance",
      infrastructure_id: infr_eth.id
    })

    insert(:exchange_address, %{
      address: "0x54321",
      name: "Kraken",
      infrastructure_id: infr_xrp.id
    })

    query = """
    {
      allExchangeWallets{
        address
        name
        infrastructure{
          code
        }
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "allExchangeWallets"))

    exchange_wallets = json_response(result, 200)["data"]["allExchangeWallets"]

    assert %{"name" => "Binance", "address" => "0x12345", "infrastructure" => %{"code" => "ETH"}} in exchange_wallets

    assert %{"name" => "Kraken", "address" => "0x54321", "infrastructure" => %{"code" => "XRP"}} in exchange_wallets
  end
end
