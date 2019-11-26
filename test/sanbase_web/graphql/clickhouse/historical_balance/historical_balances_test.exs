defmodule SanbaseWeb.Graphql.Clickhouse.HistoricalBalancesTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Mock
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]
  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.DateTimeUtils

  require Sanbase.ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000
  setup do
    project_without_contract = insert(:project, %{slug: "someid1"})

    project_with_contract =
      insert(:project, %{
        main_contract_address: "0x123",
        slug: "someid2",
        token_decimals: 18
      })

    insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [
      project_with_contract: project_with_contract,
      project_without_contract: project_without_contract,
      address: "0x321321321",
      from: from_iso8601!("2017-05-11T00:00:00Z"),
      to: from_iso8601!("2017-05-20T00:00:00Z"),
      interval: "1d"
    ]
  end

  test "historical balances when interval is bigger than balances values interval", context do
    dt1 = DateTimeUtils.from_iso8601!("2017-05-11T00:00:00Z") |> DateTime.to_unix()
    dt2 = DateTimeUtils.from_iso8601!("2017-05-12T00:00:00Z") |> DateTime.to_unix()
    dt3 = DateTimeUtils.from_iso8601!("2017-05-13T00:00:00Z") |> DateTime.to_unix()
    dt4 = DateTimeUtils.from_iso8601!("2017-05-14T00:00:00Z") |> DateTime.to_unix()
    dt5 = DateTimeUtils.from_iso8601!("2017-05-15T00:00:00Z") |> DateTime.to_unix()
    dt6 = DateTimeUtils.from_iso8601!("2017-05-16T00:00:00Z") |> DateTime.to_unix()
    dt7 = DateTimeUtils.from_iso8601!("2017-05-17T00:00:00Z") |> DateTime.to_unix()
    dt8 = DateTimeUtils.from_iso8601!("2017-05-18T00:00:00Z") |> DateTime.to_unix()
    dt9 = DateTimeUtils.from_iso8601!("2017-05-19T00:00:00Z") |> DateTime.to_unix()
    dt10 = DateTimeUtils.from_iso8601!("2017-05-20T00:00:00Z") |> DateTime.to_unix()

    with_mock Sanbase.ClickhouseRepo, [:passthrough],
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [dt1, 0, 1],
             [dt2, 0, 1],
             [dt3, 2000 * @eth_decimals, 1],
             [dt4, 1800 * @eth_decimals, 1],
             [dt5, 0, 0],
             [dt6, 1500 * @eth_decimals, 1],
             [dt7, 1900 * @eth_decimals, 1],
             [dt8, 1000 * @eth_decimals, 1],
             [dt9, 0, 0],
             [dt10, 0, 0]
           ]
         }}
      end do
      query =
        historical_balances_query(
          "ethereum",
          context.address,
          context.from,
          context.to,
          context.interval
        )

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      historical_balance = json_response(result, 200)["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => 0.0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => 0.0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500.0, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900.0, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end
  end

  test "historical balances when last interval is not full", context do
    dt1 = DateTimeUtils.from_iso8601!("2017-05-13T00:00:00Z") |> DateTime.to_unix()
    dt2 = DateTimeUtils.from_iso8601!("2017-05-15T00:00:00Z") |> DateTime.to_unix()
    dt3 = DateTimeUtils.from_iso8601!("2017-05-17T00:00:00Z") |> DateTime.to_unix()

    with_mock Sanbase.ClickhouseRepo, [:passthrough],
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [dt1, 2000 * @eth_decimals, 1],
             [dt2, 1800 * @eth_decimals, 1],
             [dt3, 1400 * @eth_decimals, 1]
           ]
         }}
      end do
      from = from_iso8601!("2017-05-13T00:00:00Z")
      to = from_iso8601!("2017-05-18T00:00:00Z")
      query = historical_balances_query("ethereum", context.address, from, to, "2d")

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))
        |> json_response(200)

      historical_balance = result["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1400.0, "datetime" => "2017-05-17T00:00:00Z"}
             ]
    end
  end

  test "historical balances when query returns error", context do
    error = "Some error description here"

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ -> {:error, error} end do
      query =
        historical_balances_query(
          "ethereum",
          context.address,
          context.from,
          context.to,
          context.interval
        )

      assert capture_log(fn ->
               result =
                 context.conn
                 |> post("/graphql", query_skeleton(query, "historicalBalance"))
                 |> json_response(200)

               historical_balance = result["data"]["historicalBalance"]
               assert historical_balance == nil
             end) =~
               graphql_error_msg("Historical Balances", "ethereum", error)
    end
  end

  test "historical balances when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      query =
        historical_balances_query(
          "ethereum",
          context.address,
          context.from,
          context.to,
          context.interval
        )

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))

      historical_balance = json_response(result, 200)["data"]["historicalBalance"]
      assert historical_balance == []
    end
  end

  test "historical balances with project with contract", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [{{2017, 05, 11}, {0, 0, 0}}, 0, 1],
             [{{2017, 05, 12}, {0, 0, 0}}, 0, 1],
             [{{2017, 05, 13}, {0, 0, 0}}, :math.pow(10, 18) * 2000, 1],
             [{{2017, 05, 14}, {0, 0, 0}}, :math.pow(10, 18) * 1800, 1],
             [{{2017, 05, 15}, {0, 0, 0}}, 0, 0],
             [{{2017, 05, 16}, {0, 0, 0}}, :math.pow(10, 18) * 1500, 1],
             [{{2017, 05, 17}, {0, 0, 0}}, :math.pow(10, 18) * 1900, 1],
             [{{2017, 05, 18}, {0, 0, 0}}, :math.pow(10, 18) * 1000, 1],
             [{{2017, 05, 19}, {0, 0, 0}}, 0, 0],
             [{{2017, 05, 20}, {0, 0, 0}}, 0, 0]
           ]
         }}
      end do
      query =
        historical_balances_query(
          context.project_with_contract.slug,
          context.address,
          context.from,
          context.to,
          context.interval
        )

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "historicalBalance"))
        |> json_response(200)

      historical_balance = result["data"]["historicalBalance"]

      assert historical_balance == [
               %{"balance" => 0.0, "datetime" => "2017-05-11T00:00:00Z"},
               %{"balance" => 0.0, "datetime" => "2017-05-12T00:00:00Z"},
               %{"balance" => 2000.0, "datetime" => "2017-05-13T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-14T00:00:00Z"},
               %{"balance" => 1800.0, "datetime" => "2017-05-15T00:00:00Z"},
               %{"balance" => 1500.0, "datetime" => "2017-05-16T00:00:00Z"},
               %{"balance" => 1900.0, "datetime" => "2017-05-17T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-18T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-19T00:00:00Z"},
               %{"balance" => 1000.0, "datetime" => "2017-05-20T00:00:00Z"}
             ]
    end
  end

  test "historical balances with project without contract", context do
    query =
      historical_balances_query(
        context.project_without_contract.slug,
        context.address,
        context.from,
        context.to,
        context.interval
      )

    assert capture_log(fn ->
             result =
               context.conn
               |> post("/graphql", query_skeleton(query, "historicalBalance"))
               |> json_response(200)

             historical_balance = result["data"]["historicalBalance"]
             assert historical_balance == nil

             error = result["errors"] |> List.first()

             assert error["message"] =~
                      "Can't fetch Historical Balances for project with slug: someid1"
           end) =~
             "{:missing_contract, \\\"Can't find contract address of project with slug: someid1\\\"}"
  end

  test "historical balances when clickhouse returns error", context do
    error = "Something bad happened"

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:error, error}
      end do
      query =
        historical_balances_query(
          context.project_with_contract.slug,
          context.address,
          context.from,
          context.to,
          context.interval
        )

      assert capture_log(fn ->
               context.conn
               |> post("/graphql", query_skeleton(query, "historicalBalance"))
               |> json_response(200)
             end) =~
               graphql_error_msg("Historical Balances", "someid2", error)
    end
  end

  defp historical_balances_query(slug, address, from, to, interval) do
    """
      {
        historicalBalance(
            slug: "#{slug}"
            address: "#{address}",
            from: "#{from}",
            to: "#{to}",
            interval: "#{interval}"
        ){
            datetime,
            balance
        }
      }
    """
  end
end
