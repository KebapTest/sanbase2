defmodule SanbaseWeb.Graphql.BlockchainAddressApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.BlockchainAddress.BlockchainAddressUserPair

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    eth_infrastructure = insert(:infrastructure, code: "ETH")

    %{
      user: user,
      conn: conn,
      eth_infrastructure: eth_infrastructure
    }
  end

  test "fetch (create) a non-existing blockchain address", context do
    result =
      blockchain_address(context.conn, %{
        address: "0x123",
        infrastructure: "ETH"
      })
      |> get_in(["data", "blockchainAddress"])

    assert result["address"] == "0x123"
    assert result["infrastructure"] == "ETH"
    assert result["labels"] == []
    assert result["notes"] == nil
  end

  test "fetch an existing blockchain address by id", context do
    address_id =
      blockchain_address(context.conn, %{
        address: "0x123",
        infrastructure: "ETH"
      })
      |> get_in(["data", "blockchainAddress", "id"])

    result =
      blockchain_address(context.conn, %{id: address_id})
      |> get_in(["data", "blockchainAddress"])

    # The same address if fetched and a new one is not created
    assert result["id"] == address_id

    assert result["address"] == "0x123"
    assert result["infrastructure"] == "ETH"
    assert result["labels"] == []
    assert result["notes"] == nil
  end

  test "fetch an existing blockchain address by address and infrastructure",
       context do
    blockchain_address =
      insert(:blockchain_address,
        address: "0x123",
        infrastructure: context.eth_infrastructure
      )

    result =
      blockchain_address(context.conn, %{
        address: "0x123",
        infrastructure: context.eth_infrastructure.code
      })
      |> get_in(["data", "blockchainAddress"])

    # The same address if fetched and a new one is not created
    assert result["id"] == blockchain_address.id
    assert result["address"] == "0x123"
    assert result["infrastructure"] == "ETH"
    assert result["labels"] == []
    assert result["notes"] == nil
  end

  test "update a blockchain address user pair", context do
    blockchain_address =
      insert(:blockchain_address,
        address: "0x123",
        infrastructure: context.eth_infrastructure
      )

    {:ok, [pair]} =
      BlockchainAddressUserPair.maybe_create([
        %{
          user_id: context.user.id,
          blockchain_address_id: blockchain_address.id
        }
      ])

    notes = "some new notes"
    labels = ["cex trader", "whale", "eth"]

    result =
      update_blockchain_address_user_pair(context.conn, pair.id, notes, labels)
      |> get_in(["data", "updateBlockchainAddressUserPair"])

    assert result["id"] == pair.id
    assert result["notes"] == "some new notes"

    assert result["labels"] == [
             %{"name" => "cex trader"},
             %{"name" => "whale"},
             %{"name" => "eth"}
           ]

    assert result["blockchainAddress"]["address"] == blockchain_address.address
    assert result["user"]["id"] |> Sanbase.Math.to_integer() == context.user.id
  end

  test "error updating a non-existining blockchain address user pair", context do
    result = update_blockchain_address_user_pair(context.conn, 15_123_123, "notes", [])

    %{"errors" => [%{"message" => error_msg}]} = result
    assert error_msg =~ "Blockchain address pair with 15123123 does not exist"
  end

  defp blockchain_address(conn, selector) do
    query = """
    {
      blockchainAddress(selector: #{map_to_input_object_str(selector)}){
        id
        address
        infrastructure
        notes
        labels{ name }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp update_blockchain_address_user_pair(conn, id, notes, labels) do
    mutation = """
    mutation {
      updateBlockchainAddressUserPair(
        id: #{id}
        notes: "#{notes}"
        labels: #{string_list_to_string(labels)}
      ){
        id
        notes
        labels{ name }
        blockchainAddress{
          address
          infrastructure
        }
        user{
          id
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end
end
