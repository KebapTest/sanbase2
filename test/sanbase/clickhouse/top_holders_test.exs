defmodule Sanbase.Clickhouse.TopHoldersTest do
  use Sanbase.DataCase
  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]
  alias Sanbase.Clickhouse.TopHolders
  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [
      slug: project.slug,
      contract: "ETH",
      token_decimals: 18,
      interval: "1d",
      number_of_holders: 10,
      from: from_iso8601!("2019-01-01T00:00:00Z"),
      to: from_iso8601!("2019-01-03T00:00:00Z")
    ]
  end

  test "returns data when clickhouse returns", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!("2019-01-01T00:00:00Z"), 7.6, 5.2, 12.8],
             [from_iso8601_to_unix!("2019-01-02T00:00:00Z"), 7.1, 5.1, 12.2]
           ]
         }}
      end do
      result =
        TopHolders.percent_of_total_supply(
          context.contract,
          context.token_decimals,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
        )

      assert result ==
               {:ok,
                [
                  %{
                    in_exchanges: 7.6,
                    outside_exchanges: 5.2,
                    in_top_holders_total: 12.8,
                    datetime: from_iso8601!("2019-01-01T00:00:00Z")
                  },
                  %{
                    in_exchanges: 7.1,
                    outside_exchanges: 5.1,
                    in_top_holders_total: 12.2,
                    datetime: from_iso8601!("2019-01-02T00:00:00Z")
                  }
                ]}
    end
  end

  test "returns empty array when query returns no rows", context do
    with_mock Sanbase.ClickhouseRepo, query: fn _, _ -> {:ok, %{rows: []}} end do
      result =
        TopHolders.percent_of_total_supply(
          context.contract,
          context.token_decimals,
          context.number_of_holders,
          context.from,
          context.to,
          context.interval
        )

      assert result == {:ok, []}
    end
  end
end
