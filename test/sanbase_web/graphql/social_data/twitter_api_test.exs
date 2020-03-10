defmodule Sanbase.Github.TwitterApiTest do
  use SanbaseWeb.ConnCase, async: false

  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Twitter.Store
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.InfluxdbHelpers

  setup do
    setup_twitter_influxdb()

    datetime1 = DateTime.from_naive!(~N[2017-05-13 18:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-05-14 18:00:00], "Etc/UTC")
    datetime3 = DateTime.from_naive!(~N[2017-05-15 18:00:00], "Etc/UTC")

    datetime_no_activity1 = DateTime.from_naive!(~N[2010-05-13 18:00:00], "Etc/UTC")
    datetime_no_activity2 = DateTime.from_naive!(~N[2010-05-15 18:00:00], "Etc/UTC")

    %Project{}
    |> Project.changeset(%{
      name: "Santiment",
      ticker: "SAN",
      twitter_link: "https://twitter.com/santimentfeed",
      slug: "santiment"
    })
    |> Repo.insert!()

    # All tests implicitly test for when more than one record has the same ticker
    %Project{}
    |> Project.changeset(%{
      name: "Santiment2",
      ticker: "SAN",
      twitter_link: ""
    })
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{
      name: "TestProj3",
      ticker: "SAN",
      twitter_link: "https://m.twitter.com/some_test_acc3",
      slug: "test3"
    })
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{
      name: "TestProj",
      ticker: "TEST1",
      twitter_link: "https://twitter.com/some_test_acc",
      slug: "test1"
    })
    |> Repo.insert!()

    %Project{}
    |> Project.changeset(%{
      name: "TestProj2",
      ticker: "TEST2",
      twitter_link: "https://m.twitter.com/some_test_acc2",
      slug: "test2"
    })
    |> Repo.insert!()

    Store.import([
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 500},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 1000},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 1500},
        name: "santimentfeed"
      },
      %Measurement{
        timestamp: datetime2 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 5},
        name: "some_test_acc"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 10},
        name: "some_test_acc"
      },
      %Measurement{
        timestamp: datetime3 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 509},
        name: "some_test_acc3"
      },
      %Measurement{
        timestamp: datetime1 |> DateTime.to_unix(:nanosecond),
        fields: %{followers_count: 454},
        name: "some_test_acc3"
      }
    ])

    [
      datetime1: datetime1,
      datetime2: datetime2,
      datetime3: datetime3,
      datetime_no_activity1: datetime_no_activity1,
      datetime_no_activity2: datetime_no_activity2
    ]
  end

  test "fetching last twitter data", context do
    query = """
    {
      twitterData(slug: "santiment") {
          followersCount
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "twitterData"))

    twitter_data = json_response(result, 200)["data"]["twitterData"]

    assert twitter_data["followersCount"] == 1500
  end

  test "fetching last twitter data for a project with invalid twitter link", context do
    query = """
    {
      twitterData(slug: "test2") {
        followersCount
      }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "twitterData"))

    twitter_data = json_response(result, 200)["data"]["twitterData"]

    assert twitter_data["followersCount"] == nil
  end

  test "fetch history twitter data when no interval is provided", context do
    query = """
    {
      historyTwitterData(
        slug: "santiment",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}"){
          followersCount
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyTwitterData"))

    history_twitter_data = json_response(result, 200)["data"]["historyTwitterData"]

    assert %{"followersCount" => 500} in history_twitter_data
    assert %{"followersCount" => 1000} in history_twitter_data
    assert %{"followersCount" => 1500} in history_twitter_data
  end

  test "fetch history twitter data", context do
    query = """
    {
      historyTwitterData(
        slug: "santiment",
        from: "#{context.datetime1}",
        to: "#{context.datetime3}",
        interval: "6h"){
          followersCount
        }
    }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "historyTwitterData"))

    history_twitter_data = json_response(result, 200)["data"]["historyTwitterData"]

    assert %{"followersCount" => 500} in history_twitter_data
    assert %{"followersCount" => 1000} in history_twitter_data
    assert %{"followersCount" => 1500} in history_twitter_data
  end
end
