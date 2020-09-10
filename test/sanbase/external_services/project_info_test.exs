defmodule Sanbase.ExternalServices.ProjectInfoTest do
  use Sanbase.DataCase, async: false

  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo
  alias Sanbase.Tag

  test "creating project info from a project" do
    project =
      %Project{
        slug: "slug",
        name: "Name",
        website_link: "website.link.com",
        email: "email@link.com",
        reddit_link: "reddit.link.com",
        twitter_link: "twitter.link.com",
        btt_link: "bitcointalk.link.com",
        blog_link: "blog.link.com",
        github_link: "github.link.com",
        telegram_link: "telegram.link.com",
        slack_link: "slack.link.com",
        facebook_link: "facebook.link.com",
        whitepaper_link: "whitepaper.link.com",
        ticker: "SAN",
        token_decimals: 4,
        total_supply: 50_000
      }
      |> Repo.insert!()

    %Ico{project_id: project.id}
    |> Repo.insert!()

    expected_project_info = %ProjectInfo{
      slug: "slug",
      name: "Name",
      website_link: "website.link.com",
      email: "email@link.com",
      reddit_link: "reddit.link.com",
      twitter_link: "twitter.link.com",
      btt_link: "bitcointalk.link.com",
      blog_link: "blog.link.com",
      github_link: "github.link.com",
      telegram_link: "telegram.link.com",
      slack_link: "slack.link.com",
      facebook_link: "facebook.link.com",
      whitepaper_link: "whitepaper.link.com",
      ticker: "SAN",
      token_decimals: 4,
      total_supply: 50_000
    }

    assert expected_project_info == ProjectInfo.from_project(project)
  end

  test "updating project info if there is no ico attached to it" do
    project =
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
          github_link: "https://github.com/santiment",
          main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
          contract_block_number: 3_972_935,
          token_decimals: 18
        },
        project
      )

    assert project.github_link == "https://github.com/santiment"
    assert project.token_decimals == 18

    assert project.main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"

    assert Project.initial_ico(project).contract_block_number == 3_972_935
  end

  test "updating project info if there is ico attached to it" do
    project =
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    ico =
      %Ico{project_id: project.id}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
          github_link: "https://github.com/santiment",
          main_contract_address: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
          contract_block_number: 3_972_935
        },
        project
      )

    assert project.github_link == "https://github.com/santiment"
    assert project.main_contract_address == "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098"
    assert Project.initial_ico(project).id == ico.id

    assert Project.initial_ico(project).contract_block_number == 3_972_935
  end

  test "update project_info with new ticker inserts into tags" do
    ticker = "SAN"

    project =
      %Project{slug: "santiment", name: "Santiment"}
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
          ticker: "SAN"
        },
        project
      )

    assert project.ticker == ticker
    assert Tag |> Repo.one() |> Map.get(:name) == ticker
  end

  test "update project_info with ticker - does not insert into tags if duplicate tag" do
    ticker = "SAN"

    %Tag{name: ticker}
    |> Repo.insert!()

    project =
      %Project{slug: "santiment", name: "Santiment", ticker: "OLD_TICKR"}
      |> Repo.insert!()

    assert capture_log(fn ->
             ProjectInfo.update_project(
               %ProjectInfo{
                 name: "Santiment",
                 slug: "santiment",
                 ticker: "SAN"
               },
               project
             )
           end) =~ "has already been taken"
  end

  test "updating the project info of a project with a contract address" do
    curr_contract = build(:contract_address)
    contract = build(:contract_address)

    project =
      %Project{
        slug: "santiment",
        name: "Santiment",
        main_contract_address: curr_contract.address,
        contract_addresses: [curr_contract]
      }
      |> Repo.insert!()

    {:ok, project} =
      ProjectInfo.update_project(
        %ProjectInfo{
          name: "Santiment",
          slug: "santiment",
          main_contract_address: contract.address
        },
        project
      )

    assert Enum.find(project.contract_addresses, &(&1.address == contract.label != "main"))
  end
end
