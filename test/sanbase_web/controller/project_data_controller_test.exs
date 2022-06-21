defmodule SanbaseWeb.ProjectDataControllerTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  alias Sanbase.Model.LatestCoinmarketcapData

  setup do
    p1 =
      insert(:random_erc20_project,
        github_organizations: [
          build(:github_organization),
          build(:github_organization),
          build(:github_organization)
        ]
      )
      |> update_latest_coinmarketcap_data(%{rank: 20})

    p2 = insert(:random_erc20_project, telegram_chat_id: 123)
    p3 = insert(:random_erc20_project)

    insert(:social_volume_query, %{project: p3, autogenerated_query: "x OR y"})
    %{p1: p1, p2: p2, p3: p3}
  end

  test "fetch data", context do
    result =
      context.conn
      |> get("/projects_data")
      |> response(200)
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert project_data(context.p1, context) in result
    assert project_data(context.p2, context) in result
    assert project_data(context.p3, context) in result
  end

  defp project_data(project, context) do
    infrastructure = Project.infrastructure(project)
    {:ok, contract, decimals} = Project.contract_info(project)
    {:ok, github_organizations} = Project.github_organizations(project)

    new_fields =
      cond do
        project.id == context.p1.id ->
          %{"social_volume_query" => "", "rank" => 20, "telegram_chat_id" => nil}

        project.id == context.p2.id ->
          %{"social_volume_query" => "", "rank" => nil, "telegram_chat_id" => 123}

        project.id == context.p3.id ->
          %{"social_volume_query" => "x OR y", "rank" => nil, "telegram_chat_id" => nil}
      end

    %{
      "contract" => contract,
      "decimals" => decimals,
      "ticker" => project.ticker,
      "slug" => project.slug,
      "infrastructure" => infrastructure.code,
      "github_organizations" => github_organizations |> Enum.sort() |> Enum.join(",")
    }
    |> Map.merge(new_fields)
  end

  defp update_latest_coinmarketcap_data(project, args) do
    %LatestCoinmarketcapData{}
    |> LatestCoinmarketcapData.changeset(
      %{
        coinmarketcap_id: project.slug,
        update_time: Timex.now()
      }
      |> Map.merge(args)
    )
    |> Repo.insert_or_update()

    Repo.get!(Project, project.id)
  end
end
