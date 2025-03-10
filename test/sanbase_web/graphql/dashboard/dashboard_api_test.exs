defmodule SanbaseWeb.Graphql.DashboardApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  describe "voting" do
    test "vote and get votes", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      vote = fn ->
        context.conn
        |> post(
          "/graphql",
          mutation_skeleton("mutation{ vote(dashboardId: #{dashboard_id}) { votedAt } }")
        )
      end

      for _ <- 1..10, do: vote.()

      total_votes =
        get_dashboard_schema(context.conn, dashboard_id)
        |> get_in(["data", "getDashboardSchema", "votes", "totalVotes"])

      assert total_votes == 10
    end
  end

  describe "create/update/delete dashboard" do
    test "create", context do
      result =
        execute_dashboard_mutation(context.conn, :create_dashboard, %{
          name: "MyDashboard",
          description: "some text",
          is_public: true
        })
        |> get_in(["data", "createDashboard"])

      user_id = context.user.id |> to_string()

      assert %{
               "name" => "MyDashboard",
               "description" => "some text",
               "panels" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "update", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      result =
        execute_dashboard_mutation(context.conn, :update_dashboard, %{
          id: dashboard_id,
          name: "MyDashboard - update",
          description: "some text - update",
          is_public: false
        })
        |> get_in(["data", "updateDashboard"])

      user_id = context.user.id |> to_string()

      assert %{
               "id" => ^dashboard_id,
               "name" => "MyDashboard - update",
               "description" => "some text - update",
               "panels" => [],
               "user" => %{"id" => ^user_id}
             } = result
    end

    test "delete", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      execute_dashboard_mutation(context.conn, :remove_dashboard, %{id: dashboard_id})

      assert {:error, error_msg} = Sanbase.Dashboard.load_schema(dashboard_id)
      assert error_msg =~ "does not exist"
    end
  end

  describe "create/update/delete panels" do
    test "create panel", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      result =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard_id)
        )
        |> get_in(["data", "createDashboardPanel"])

      assert %{
               "id" => binary_id,
               "dashboardId" => ^dashboard_id,
               "sql" => %{
                 # The `slug` parameter` is inherited from the dashboard
                 "parameters" => %{"limit" => 20},
                 "query" =>
                   "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})"
               }
             } = result

      assert is_binary(binary_id)
    end

    test "update panel", context do
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard_id)
        )
        |> get_in(["data", "createDashboardPanel"])

      updated_panel =
        execute_dashboard_panel_schema_mutation(context.conn, :update_dashboard_panel, %{
          dashboard_id: dashboard_id,
          panel_id: panel["id"],
          panel: %{
            map_as_input_object: true,
            name: "New name",
            sql: %{
              map_as_input_object: true,
              query: "SELECT * FROM intraday_metrics LIMIT {{limit}}",
              parameters: Jason.encode!(%{"limit" => 20})
            }
          }
        })
        |> get_in(["data", "updateDashboardPanel"])

      assert %{
               "id" => panel["id"],
               "name" => "New name",
               "dashboardId" => dashboard_id,
               "sql" => %{
                 "parameters" => %{"limit" => 20},
                 "query" => "SELECT * FROM intraday_metrics LIMIT {{limit}}"
               },
               "settings" => nil
             } == updated_panel
    end

    test "remove panel", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      assert dashboard["panels"] == []

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      assert get_in(dashboard, ["panels", Access.at(0), "id"]) == panel["id"]

      execute_dashboard_panel_schema_mutation(context.conn, :remove_dashboard_panel, %{
        dashboard_id: dashboard["id"],
        panel_id: panel["id"]
      })

      dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      assert dashboard["panels"] == []
    end

    test "concurrent actions - create panels", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      # Create 20 panels concurrently
      panels =
        Sanbase.Parallel.map(
          1..20,
          fn _ ->
            execute_dashboard_panel_schema_mutation(
              context.conn,
              :create_dashboard_panel,
              default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
            )
            |> get_in(["data", "createDashboardPanel"])
          end,
          max_concurrency: 10,
          ordered: false
        )

      assert length(panels) == 20
      assert Enum.all?(panels, &is_binary(&1["id"]))

      updated_dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      # Test that each of the panels created panels is properly stored in the
      # dashboard and returned in the subsequent query
      Enum.each(panels, fn %{"id" => panel_id} ->
        assert Enum.find(updated_dashboard["panels"], fn %{"id" => id} -> id == panel_id end)
      end)
    end

    test "concurrent actions - update panels", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panels =
        for _ <- 1..2 do
          execute_dashboard_panel_schema_mutation(
            context.conn,
            :create_dashboard_panel,
            default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
          )
          |> get_in(["data", "createDashboardPanel"])
        end

      # Update all 20 panels concurrently
      updated_panels =
        Sanbase.Parallel.map(panels, fn panel ->
          execute_dashboard_panel_schema_mutation(context.conn, :update_dashboard_panel, %{
            dashboard_id: dashboard["id"],
            panel_id: panel["id"],
            panel: %{
              map_as_input_object: true,
              name: "New name",
              settings: %{layout: [1, 2, 5, 10]}
            }
          })
          |> get_in(["data", "updateDashboardPanel"])
        end)

      updated_dashboard =
        get_dashboard_schema(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardSchema"])

      Enum.each(updated_panels, fn %{"id" => panel_id, "settings" => settings, "name" => name} ->
        assert Enum.find(updated_dashboard["panels"], fn %{"id" => id} -> id == panel_id end)
        assert name == "New name"
        assert settings == %{"layout" => [1, 2, 5, 10]}
      end)
    end
  end

  describe "compute and get cache" do
    test "compute a panel", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_dashboard_panel_cache_mutation(context.conn, :compute_dashboard_panel, %{
            dashboard_id: dashboard["id"],
            panel_id: panel["id"]
          })

        dashboard_id = dashboard["id"]

        assert %{
                 "data" => %{
                   "computeDashboardPanel" => %{
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                     "dashboardId" => ^dashboard_id,
                     "id" => _,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                     ],
                     "summary" => %{
                       "read_bytes" => "0",
                       "read_rows" => "0",
                       "total_rows_to_read" => "0",
                       "written_bytes" => "0",
                       "written_rows" => "0"
                     },
                     "updatedAt" => updated_at
                   }
                 }
               } = result

        updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
      end)
    end

    test "compute and store panels", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      # Test with more than 1 panel so it makes sure that existing cache is
      # kept intact
      panel1 =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      panel2 =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            # There is a sleep of 8000ms before the execution details are queried
            # Because of that the order of mocks here is listed as it is
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        execute_dashboard_panel_cache_mutation(
          context.conn,
          :compute_and_store_dashboard_panel,
          %{
            dashboard_id: dashboard["id"],
            panel_id: panel1["id"]
          }
        )

        result =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_and_store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel2["id"]
            }
          )
          |> get_in(["data", "computeAndStoreDashboardPanel"])

        dashboard_id = dashboard["id"]

        assert %{
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 "dashboardId" => ^dashboard_id,
                 "id" => id,
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => "0",
                   "read_rows" => "0",
                   "total_rows_to_read" => "0",
                   "written_bytes" => "0",
                   "written_rows" => "0"
                 },
                 "updatedAt" => updated_at
               } = result

        assert is_binary(id) and String.length(id) == 36
        updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
        assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
      end)

      # Run the next part outside the mock, so if there's data it's not coming from Clickhouse

      # Get the whole dashboard cache
      dashboard_cache =
        get_dashboard_cache(context.conn, dashboard["id"])
        |> get_in(["data", "getDashboardCache"])

      dashboard_id = dashboard["id"]

      assert %{"panels" => panels} = dashboard_cache
      assert length(panels) == 2

      for panel_id <- [panel1["id"], panel2["id"]] do
        assert Enum.any?(
                 panels,
                 &match?(
                   %{
                     "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "dashboardId" => ^dashboard_id,
                     "id" => ^panel_id,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                     ],
                     "summary" => %{
                       "read_bytes" => "0",
                       "read_rows" => "0",
                       "total_rows_to_read" => "0",
                       "written_bytes" => "0",
                       "written_rows" => "0"
                     },
                     "updatedAt" => _
                   },
                   &1
                 )
               )
      end

      # Get a single dashboard panel cache
      panel2_id = panel2["id"]

      panel2_cache =
        get_dashboard_panel_cache(context.conn, dashboard_id, panel2_id)
        |> get_in(["data", "getDashboardPanelCache"])

      assert %{
               "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
               "dashboardId" => ^dashboard_id,
               "id" => id,
               "rows" => [
                 [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                 [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
               ],
               "summary" => %{
                 "read_bytes" => "0",
                 "read_rows" => "0",
                 "total_rows_to_read" => "0",
                 "written_bytes" => "0",
                 "written_rows" => "0"
               },
               "updatedAt" => updated_at
             } = panel2_cache

      assert is_binary(id) and String.length(id) == 36
      updated_at = Sanbase.DateTimeUtils.from_iso8601!(updated_at)
      assert Sanbase.TestUtils.datetime_close_to(Timex.now(), updated_at, 2, :seconds)
    end

    test "compute panel and store it with a separate mutation", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"]
            }
          )
          |> get_in(["data", "computeDashboardPanel"])

        stored =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"],
              panel: %{
                map_as_input_object: true,
                clickhouse_query_id: result["clickhouseQueryId"],
                columns: result["columns"],
                column_types: result["columnTypes"],
                rows: Jason.encode!(result["rows"]),
                summary: Jason.encode!(result["summary"]),
                query_start_time: result["queryStartTime"],
                query_end_time: result["queryEndTime"]
              }
            }
          )
          |> get_in(["data", "storeDashboardPanel"])

        dashboard_id = dashboard["id"]
        panel_id = panel["id"]
        query_start_time = result["queryStartTime"]
        query_end_time = result["queryEndTime"]

        assert %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "dashboardId" => ^dashboard_id,
                 "id" => ^panel_id,
                 "queryEndTime" => ^query_start_time,
                 "queryStartTime" => ^query_end_time,
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => "0",
                   "read_rows" => "0",
                   "total_rows_to_read" => "0",
                   "written_bytes" => "0",
                   "written_rows" => "0"
                 },
                 "updatedAt" => _
               } = stored

        dashboard_cache =
          get_dashboard_cache(context.conn, dashboard["id"])
          |> get_in(["data", "getDashboardCache"])

        dashboard_id = dashboard["id"]

        assert %{
                 "panels" => [
                   %{
                     "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                     "dashboardId" => ^dashboard_id,
                     "id" => ^panel_id,
                     "rows" => [
                       [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                       [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                     ],
                     "summary" => %{
                       "read_bytes" => "0",
                       "read_rows" => "0",
                       "total_rows_to_read" => "0",
                       "written_bytes" => "0",
                       "written_rows" => "0"
                     },
                     "updatedAt" => _
                   }
                 ]
               } = dashboard_cache
      end)
    end

    test "cannot store result bigger than the allowed limit", context do
      dashboard =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard"])

      panel =
        execute_dashboard_panel_schema_mutation(
          context.conn,
          :create_dashboard_panel,
          default_dashboard_panel_args() |> Map.put(:dashboard_id, dashboard["id"])
        )
        |> get_in(["data", "createDashboardPanel"])

      mock = mocked_clickhouse_result()

      # seed the rand generator so it gives the same result every time
      :rand.seed(:default, 42)

      rows =
        for i <- 1..25_000 do
          [
            0 + :rand.uniform(1000),
            0 + :rand.uniform(1000),
            "2008-#{rem(i, 12) + 1}-10T00:00:00Z",
            :rand.uniform() * 1000,
            "2020-#{rem(i, 12) + 1}-28T15:18:42Z"
          ]
        end

      mock = Map.put(mock, :rows, rows)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, mock}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        error_msg =
          execute_dashboard_panel_cache_mutation(
            context.conn,
            :compute_and_store_dashboard_panel,
            %{
              dashboard_id: dashboard["id"],
              panel_id: panel["id"]
            }
          )
          |> get_in(["errors", Access.at(0), "message"])

        assert error_msg =~
                 "Cannot cache the panel because its compressed size is 517.88KB which is over the limit of 500KB"
      end)
    end
  end

  describe "execute raw queries" do
    test "compute raw clickhouse query", context do
      args = %{
        query:
          "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}}) LIMIT {{limit}}",
        parameters: %{slug: "bitcoin", limit: 2},
        map_as_input_object: true
      }

      query = """
      {
        computeRawClickhouseQuery(#{map_to_args(args)}){
          columns
          columnTypes
          rows
          clickhouseQueryId
          summary
        }
      }
      """

      mock_fun =
        Sanbase.Mock.wrap_consecutives(
          [
            fn -> {:ok, mocked_clickhouse_result()} end,
            fn -> {:ok, mocked_execution_details_result()} end
          ],
          arity: 2
        )

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          context.conn
          |> post("/graphql", query_skeleton(query))
          |> json_response(200)
          |> get_in(["data", "computeRawClickhouseQuery"])

        assert result == %{
                 "clickhouseQueryId" => "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
                 "columns" => ["asset_id", "metric_id", "dt", "value", "computed_at"],
                 "columnTypes" => ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
                 "rows" => [
                   [2503, 250, "2008-12-10T00:00:00Z", 0.0, "2020-02-28T15:18:42Z"],
                   [2503, 250, "2008-12-10T00:05:00Z", 0.0, "2020-02-28T15:18:42Z"]
                 ],
                 "summary" => %{
                   "read_bytes" => "0",
                   "read_rows" => "0",
                   "total_rows_to_read" => "0",
                   "written_bytes" => "0",
                   "written_rows" => "0"
                 }
               }
      end)
    end

    defp mocked_clickhouse_result() do
      %Clickhousex.Result{
        columns: ["asset_id", "metric_id", "dt", "value", "computed_at"],
        column_types: ["UInt64", "UInt64", "DateTime", "Float64", "DateTime"],
        command: :selected,
        num_rows: 2,
        query_id: "177a5a3d-072b-48ac-8cf5-d8375c8314ef",
        rows: [
          [2503, 250, ~N[2008-12-10 00:00:00], 0.0, ~N[2020-02-28 15:18:42]],
          [2503, 250, ~N[2008-12-10 00:05:00], 0.0, ~N[2020-02-28 15:18:42]]
        ],
        summary: %{
          "read_bytes" => "0",
          "read_rows" => "0",
          "total_rows_to_read" => "0",
          "written_bytes" => "0",
          "written_rows" => "0"
        }
      }
    end
  end

  defp mocked_execution_details_result() do
    %Clickhousex.Result{
      query_id: "1774C4BC91E058D4",
      summary: %{
        "read_bytes" => "5069080",
        "read_rows" => "167990",
        "result_bytes" => "0",
        "result_rows" => "0",
        "total_rows_to_read" => "167990",
        "written_bytes" => "0",
        "written_rows" => "0"
      },
      command: :selected,
      columns: [
        "read_compressed_gb",
        "cpu_time_microseconds",
        "query_duration_ms",
        "memory_usage_gb",
        "read_rows",
        "read_gb",
        "result_rows",
        "result_gb"
      ],
      column_types: [
        "Float64",
        "UInt64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64",
        "UInt64",
        "Float64"
      ],
      rows: [
        [
          # read_compressed_gb
          0.001110738143324852,
          # cpu_time_microseconds
          101_200,
          # query_duration_ms
          47,
          # memory_usage_gb
          0.03739274851977825,
          # read_rows
          364_923,
          # read_gb
          0.01087852381169796,
          # result_rows
          2,
          # result_gb
          2.980232238769531e-7
        ]
      ],
      num_rows: 1
    }
  end

  describe "keep dashboard history" do
    test "keep dashboard history", context do
      # Create empty dashboard
      dashboard_id =
        execute_dashboard_mutation(context.conn, :create_dashboard)
        |> get_in(["data", "createDashboard", "id"])

      # Store the dashboard schema
      hash1 =
        store_dashboard_schema_history(
          context.conn,
          %{id: dashboard_id, message: "Store initial version of dashboard schema"}
        )
        |> get_in(["data", "storeDashboardSchemaHistory", "hash"])

      # Add a panel to the dashboard
      execute_dashboard_panel_schema_mutation(
        context.conn,
        :create_dashboard_panel,
        default_dashboard_panel_args()
        |> Map.put(:dashboard_id, dashboard_id)
      )
      |> get_in(["data", "createDashboardPanel"])

      # Store the dashboard schema again
      hash2 =
        store_dashboard_schema_history(
          context.conn,
          %{id: dashboard_id, message: "Store second version"}
        )
        |> get_in(["data", "storeDashboardSchemaHistory", "hash"])

      history_list =
        get_dashboard_schema_history_list(context.conn, dashboard_id)
        |> get_in(["data", "getDashboardSchemaHistoryList"])

      assert [
               %{
                 "hash" => ^hash2,
                 "insertedAt" => _,
                 "message" => "Store second version"
               },
               %{
                 "hash" => ^hash1,
                 "insertedAt" => _,
                 "message" => "Store initial version of dashboard schema"
               }
             ] = history_list

      schema_history1 =
        get_dashboard_schema_history(context.conn, dashboard_id, hash1)
        |> get_in(["data", "getDashboardSchemaHistory"])

      assert %{
               "description" => "some text",
               "hash" => ^hash1,
               "insertedAt" => _,
               "isPublic" => true,
               "message" => "Store initial version of dashboard schema",
               "name" => "MyDashboard",
               "panels" => []
             } = schema_history1

      schema_history2 =
        get_dashboard_schema_history(context.conn, dashboard_id, hash2)
        |> get_in(["data", "getDashboardSchemaHistory"])

      assert %{
               "description" => "some text",
               "hash" => ^hash2,
               "insertedAt" => _,
               "isPublic" => true,
               "message" => "Store second version",
               "name" => "MyDashboard",
               "parameters" => %{},
               "panels" => [
                 %{
                   "sql" => %{
                     "parameters" => %{"limit" => 20},
                     "query" =>
                       "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})"
                   }
                 }
               ]
             } = schema_history2
    end
  end

  describe "get clickhouse database information" do
    test "get available clickhouse tables API", context do
      query = """
      {
        getAvailableClickhouseTables{
          table
          description
          columns
          engine
          orderBy
          partitionBy
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query))
        |> json_response(200)
        |> get_in(["data", "getAvailableClickhouseTables"])

      assert %{
               "columns" => %{
                 "base_asset" => "LowCardinality(String)",
                 "dt" => "DateTime",
                 "price" => "Float64",
                 "quote_asset" => "LowCardinality(String)",
                 "source" => "LowCardinality(String)"
               },
               "description" =>
                 "Provide price_usd, price_btc, volume_usd and marketcap_usd metrics for assets",
               "engine" => "ReplicatedReplacingMergeTree",
               "orderBy" => ["base_asset", "quote_asset", "source", "dt"],
               "partitionBy" => "toYYYYMM(dt)",
               "table" => "asset_prices_v3"
             } in result

      assert %{
               "columns" => %{
                 "assetRefId" => "UInt64",
                 "blockNumber" => "UInt32",
                 "contract" => "LowCardinality(String)",
                 "dt" => "DateTime",
                 "from" => "LowCardinality(String)",
                 "logIndex" => "UInt32",
                 "primaryKey" => "UInt64",
                 "to" => "LowCardinality(String)",
                 "transactionHash" => "String",
                 "value" => "Float64",
                 "valueExactBase36" => "String"
               },
               "description" => "Provide the on-chain transfers for Ethereum itself",
               "engine" => "Distributed",
               "orderBy" => ["from", "type", "to", "dt", "transactionHash", "primaryKey"],
               "partitionBy" => "toStartOfMonth(dt)",
               "table" => "erc20_transfers"
             } in result
    end

    test "get clickhouse database metadata", context do
      query = """
      {
        getClickhouseDatabaseMetadata{
          columns{ name isInSortingKey isInPartitionKey }
          tables{ name partitionKey sortingKey primaryKey }
          functions{ name origin }
        }
      }
      """

      mock_fun =
        [
          # mock columns response
          fn ->
            {:ok,
             %{
               rows: [
                 ["asset_metadata", "asset_id", "UInt64", 0, 1, 1],
                 ["asset_metadata", "computed_at", "DateTime", 0, 0, 0]
               ]
             }}
          end,
          # mock functions response
          fn -> {:ok, %{rows: [["logTrace", "System"], ["get_asset_id", "SQLUserDefined"]]}} end,
          # mock tables response
          fn ->
            {:ok,
             %{
               rows: [
                 ["asset_metadata", "ReplicatedReplacingMergeTree", "", "asset_id", "asset_id"],
                 [
                   "asset_price_pairs_only",
                   "ReplicatedReplacingMergeTree",
                   "toYYYYMM(dt)",
                   "base_asset, quote_asset, source, dt",
                   "base_asset, quote_asset, source, dt"
                 ]
               ]
             }}
          end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 2)

      Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
      |> Sanbase.Mock.run_with_mocks(fn ->
        metadata =
          post(context.conn, "/graphql", query_skeleton(query))
          |> json_response(200)
          |> get_in(["data", "getClickhouseDatabaseMetadata"])

        assert metadata == %{
                 "columns" => [
                   %{"isInPartitionKey" => false, "isInSortingKey" => true, "name" => "asset_id"},
                   %{
                     "isInPartitionKey" => false,
                     "isInSortingKey" => false,
                     "name" => "computed_at"
                   }
                 ],
                 "functions" => [
                   %{"name" => "logTrace", "origin" => "System"},
                   %{"name" => "get_asset_id", "origin" => "SQLUserDefined"}
                 ],
                 "tables" => [
                   %{
                     "name" => "asset_metadata",
                     "partitionKey" => "",
                     "primaryKey" => "asset_id",
                     "sortingKey" => "asset_id"
                   },
                   %{
                     "name" => "asset_price_pairs_only",
                     "partitionKey" => "toYYYYMM(dt)",
                     "primaryKey" => "base_asset, quote_asset, source, dt",
                     "sortingKey" => "base_asset, quote_asset, source, dt"
                   }
                 ]
               }
      end)
    end
  end

  defp store_dashboard_schema_history(conn, args) do
    mutation = """
    mutation {
      storeDashboardSchemaHistory(#{map_to_args(args)}){
        message
        hash

        dashboardId
        name
        description
        panels{
          id
          sql {
            query
            parameters
          }
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_panel_schema_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        dashboardId
        settings
        sql {
          query
          parameters
        }
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_panel_cache_mutation(conn, mutation, args) do
    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        clickhouseQueryId
        dashboardId
        columns
        columnTypes
        rows
        summary
        updatedAt
        queryStartTime
        queryEndTime
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp execute_dashboard_mutation(conn, mutation, args \\ nil) do
    args =
      args ||
        %{
          name: "MyDashboard",
          description: "some text",
          is_public: true
        }

    mutation_name = mutation |> Inflex.camelize(:lower)

    mutation = """
    mutation {
      #{mutation_name}(#{map_to_args(args)}){
        id
        name
        description
        user{ id }
        panels { id }
        parameters
      }
    }
    """

    conn
    |> post("/graphql", mutation_skeleton(mutation))
    |> json_response(200)
  end

  defp get_dashboard_schema(conn, dashboard_id) do
    query = """
    {
      getDashboardSchema(id: #{dashboard_id}){
        id
        name
        description
        isPublic
        parameters
        panels {
          id
          settings
          sql { query parameters }
        }
        votes {
          totalVotes
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard_cache(conn, dashboard_id) do
    query = """
    {
      getDashboardCache(id: #{dashboard_id}){
        panels{
          id
          dashboardId
          columns
          columnTypes
          rows
          summary
          updatedAt
        }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard_panel_cache(conn, dashboard_id, panel_id) do
    query = """
    {
      getDashboardPanelCache(dashboardId: #{dashboard_id}, panelId: "#{panel_id}"){
        id
        dashboardId
        columns
        columnTypes
        rows
        summary
        updatedAt
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard_schema_history_list(conn, dashboard_id) do
    query = """
    {
      getDashboardSchemaHistoryList(id: #{dashboard_id}, page: 1, pageSize: 10){
        message
        hash
        insertedAt
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp get_dashboard_schema_history(conn, dashboard_id, hash) do
    query = """
    {
      getDashboardSchemaHistory(id: #{dashboard_id}, hash: "#{hash}"){
        name
        description
        isPublic
        panels { sql { query parameters } }
        parameters
        message
        hash
        insertedAt
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end

  defp default_dashboard_panel_args() do
    %{
      panel: %{
        map_as_input_object: true,
        name: "My Panel",
        sql: %{
          map_as_input_object: true,
          query:
            "SELECT * FROM intraday_metrics WHERE asset_id IN (SELECT asset_id FROM asset_metadata WHERE name = {{slug}} LIMIT {{limit}})",
          parameters: Jason.encode!(%{"limit" => 20, "slug" => "bitcoin"})
        }
      }
    }
  end
end
