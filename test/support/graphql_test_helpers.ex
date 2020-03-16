defmodule SanbaseWeb.Graphql.TestHelpers do
  use Phoenix.ConnTest

  alias SanbaseWeb.Graphql.ContextPlug

  # The default endpoint for testing
  @endpoint SanbaseWeb.Endpoint

  @custom_access_metrics Sanbase.Billing.Plan.CustomAccess.get()
                         |> Enum.filter(&match?({{:metric, _}, _}, &1))
                         |> Enum.map(fn {{_, name}, _} -> name end)

  def v2_restricted_metric(position),
    do:
      (Sanbase.Metric.restricted_metrics() -- @custom_access_metrics)
      |> Stream.cycle()
      |> Enum.at(position)

  def v2_free_metric(position),
    do: Sanbase.Metric.free_metrics() |> Stream.cycle() |> Enum.at(position)

  def from_to(from_days_shift, to_days_shift) do
    from = Timex.shift(Timex.now(), days: -from_days_shift)
    to = Timex.shift(Timex.now(), days: -to_days_shift)
    {from, to}
  end

  def query_skeleton(query, query_name \\ "", variable_defs \\ "", variables \\ "{}") do
    %{
      "operationName" => "#{query_name}",
      "query" => "query #{query_name}#{variable_defs} #{query}",
      "variables" => "#{variables}"
    }
  end

  def mutation_skeleton(mutation, mutation_name \\ "") do
    %{
      "operationName" => "#{mutation_name}",
      "query" => "#{mutation}",
      "variables" => ""
    }
  end

  def setup_jwt_auth(conn, user) do
    {:ok, token, _claims} = SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt})

    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> ContextPlug.call(%{})
  end

  def setup_apikey_auth(conn, apikey) do
    conn
    |> put_req_header("authorization", "Apikey " <> apikey)
    |> ContextPlug.call(%{})
  end

  def setup_basic_auth(conn, user, pass) do
    token = Base.encode64(user <> ":" <> pass)

    conn
    |> put_req_header("authorization", "Basic " <> token)
    |> ContextPlug.call(%{})
  end

  def execute_query(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> get_in(["data", query_name])
  end

  def execute_query_with_error(conn, query, query_name) do
    conn
    |> post("/graphql", query_skeleton(query, query_name))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end

  def execute_mutation(conn, query, query_name) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> get_in(["data", query_name])
  end

  def execute_mutation_with_error(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
    |> Map.get("errors")
    |> hd()
    |> Map.get("message")
  end

  def map_to_input_object_str(%{} = map) do
    str =
      Enum.map(map, fn
        {k, v} -> ~s/#{k}: #{inspect(v)}/
      end)
      |> Enum.join(", ")

    "{" <> str <> "}"
  end

  def graphql_error_msg(metric_name, error) do
    "Can't fetch #{metric_name}, Reason: \"#{error}\""
  end

  def graphql_error_msg(metric_name, slug, error) do
    "Can't fetch #{metric_name} for project with slug: #{slug}, Reason: \"#{error}\""
  end
end
