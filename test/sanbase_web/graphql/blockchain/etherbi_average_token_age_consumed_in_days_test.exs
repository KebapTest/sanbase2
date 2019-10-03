defmodule Sanbase.Etherbi.AverageTokenAgeConsumedInDaysApiTest do
  use SanbaseWeb.ConnCase, async: false
  @moduletag checkout_repo: [Sanbase.Repo, Sanbase.TimescaleRepo]
  @moduletag timescaledb: true

  alias Sanbase.Model.Project
  alias Sanbase.Repo

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))

    conn = setup_jwt_auth(build_conn(), user)

    ticker = "SAN"
    slug = "santiment"
    contract_address = "0x1234"

    %Project{
      name: "Santiment",
      ticker: ticker,
      slug: slug,
      main_contract_address: contract_address
    }
    |> Repo.insert!()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 21:45:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-13 21:55:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-14 22:05:00], "Etc/UTC")
    datetime4 = DateTime.from_naive!(~N[2017-05-14 22:15:00], "Etc/UTC")

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime1,
      token_age_consumed: 5_000_000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime2,
      token_age_consumed: 3_640_000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime3,
      token_age_consumed: 10_000
    })

    insert(:token_age_consumed, %{
      contract_address: contract_address,
      timestamp: datetime4,
      token_age_consumed: 7_280
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime1,
      transaction_volume: 15
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime2,
      transaction_volume: 5
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime3,
      transaction_volume: 20
    })

    insert(:transaction_volume, %{
      contract_address: contract_address,
      timestamp: datetime4,
      transaction_volume: 10
    })

    [
      slug: slug,
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime4: datetime4,
      conn: conn
    ]
  end

  test "fetch token age consumed in days", context do
    query = """
    {
      averageTokenAgeConsumedInDays(
        slug: "#{context.slug}",
        from: "#{context.datetime1}",
        to: "#{context.datetime4}",
        interval: "1d") {
          datetime
          tokenAge
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "averageTokenAgeConsumedInDays"))

    token_age_consumed_in_days =
      json_response(result, 200)["data"]["averageTokenAgeConsumedInDays"]

    assert %{
             "datetime" => "2017-05-13T21:45:00Z",
             "tokenAge" => 75.0
           } in token_age_consumed_in_days

    assert %{
             "datetime" => "2017-05-14T00:00:00Z",
             "tokenAge" => 0.1
           } in token_age_consumed_in_days
  end
end
