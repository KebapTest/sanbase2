defmodule Sanbase.Clickhouse.HistoricalBalance.EthAssetsHeldByAdderssTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory

  alias Sanbase.Clickhouse.HistoricalBalance.EthBalance

  require Sanbase.ClickhouseRepo

  setup do
    project = insert(:project, %{name: "Ethereum", slug: "ethereum", ticker: "ETH"})

    {:ok, [project: project]}
  end

  test "clickhouse returns list of results", context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [1000 * Sanbase.Math.ipow(10, 18)]
           ]
         }}
      end do
      assert EthBalance.assets_held_by_address("0x123") ==
               {:ok,
                [
                  %{balance: 1000, slug: context.project.slug}
                ]}
    end
  end

  test "clickhouse returns no results", _context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: []
         }}
      end do
      assert EthBalance.assets_held_by_address("0x123") ==
               {:ok, []}
    end
  end

  test "clickhouse returns error", _context do
    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:error, "Cannot execute query due to error"}
      end do
      assert EthBalance.assets_held_by_address("0x123") ==
               {:error, "Cannot execute query due to error"}
    end
  end
end
