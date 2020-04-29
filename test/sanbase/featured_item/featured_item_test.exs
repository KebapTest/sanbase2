defmodule Sanbase.FeaturedItemTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.FeaturedItem
  alias Sanbase.Insight.Post

  describe "chart configuration featured items" do
    test "no chart configurations are featured" do
      assert FeaturedItem.insights() == []
    end

    test "marking chart configurations as featured" do
      chart_config = insert(:chart_configuration)

      FeaturedItem.update_item(chart_config, true)
      [featured_chart_config] = FeaturedItem.chart_configurations()

      assert featured_chart_config.id == chart_config.id
    end

    test "unmarking chart configurations as featured" do
      chart_config = insert(:chart_configuration)

      FeaturedItem.update_item(chart_config, true)
      FeaturedItem.update_item(chart_config, false)
      assert FeaturedItem.chart_configurations() == []
    end

    test "marking chart configuration as featured is idempotent" do
      chart_config = insert(:chart_configuration)

      FeaturedItem.update_item(chart_config, true)
      FeaturedItem.update_item(chart_config, true)
      FeaturedItem.update_item(chart_config, true)
      [featured_chart_config] = FeaturedItem.chart_configurations()
      assert featured_chart_config.id == chart_config.id
    end
  end

  describe "insight featured items" do
    test "no insights are featured" do
      assert FeaturedItem.insights() == []
    end

    test "marking insights as featured" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      FeaturedItem.update_item(insight, true)
      [featured_insight] = FeaturedItem.insights()

      assert featured_insight.id == insight.id
    end

    test "unmarking insights as featured" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, false)
      assert FeaturedItem.insights() == []
    end

    test "marking insight as featured is idempotent" do
      insight = insert(:post, state: Post.approved_state(), ready_state: Post.published())

      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)
      FeaturedItem.update_item(insight, true)
      [featured_insight] = FeaturedItem.insights()
      assert featured_insight.id == insight.id
    end
  end

  describe "watchlist featured items" do
    test "no watchlists are featured" do
      assert FeaturedItem.watchlists() == []
    end

    test "marking watchlists as featured" do
      watchlist = insert(:watchlist) |> Sanbase.Repo.preload([:list_items])
      FeaturedItem.update_item(watchlist, true)
      assert FeaturedItem.watchlists() == [watchlist]
    end

    test "unmarking watchlists as featured" do
      watchlist = insert(:watchlist)
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, false)
      assert FeaturedItem.watchlists() == []
    end

    test "marking watchlist as featured is idempotent" do
      watchlist = insert(:watchlist) |> Sanbase.Repo.preload([:list_items])
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, true)
      FeaturedItem.update_item(watchlist, true)

      assert FeaturedItem.watchlists() == [watchlist]
    end
  end

  describe "user_trigger featured items" do
    test "no user_triggers are featured" do
      assert FeaturedItem.user_triggers() == []
    end

    test "marking user_triggers as featured" do
      user_trigger = insert(:user_trigger) |> Sanbase.Repo.preload([:tags])
      FeaturedItem.update_item(user_trigger, true)
      assert FeaturedItem.user_triggers() == [user_trigger]
    end

    test "unmarking user_triggers as featured" do
      user_trigger = insert(:user_trigger)
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, false)
      assert FeaturedItem.user_triggers() == []
    end

    test "marking user_trigger as featured is idempotent" do
      user_trigger = insert(:user_trigger) |> Sanbase.Repo.preload([:tags])
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, true)
      FeaturedItem.update_item(user_trigger, true)

      assert FeaturedItem.user_triggers() == [user_trigger]
    end
  end
end
