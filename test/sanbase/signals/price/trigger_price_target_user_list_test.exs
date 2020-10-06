defmodule SanbaseWeb.Graphql.TargetUserListTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import ExUnit.CaptureLog
  import Sanbase.TestHelpers

  alias Sanbase.UserList
  alias Sanbase.Signal.UserTrigger

  setup do
    clean_task_supervisor_children()

    user = insert(:user, user_settings: %{settings: %{signal_notify_telegram: true}})

    p1 =
      insert(:project, %{
        name: "Santiment",
        ticker: "SAN",
        slug: "santiment",
        main_contract_address: "0x123123"
      })

    p2 =
      insert(:project, %{
        name: "Maker",
        ticker: "MKR",
        slug: "maker",
        main_contract_address: "0x321321321"
      })

    {:ok, user_list} = UserList.create_user_list(user, %{name: "my_user_list", color: :green})

    UserList.update_user_list(%{
      id: user_list.id,
      list_items: [%{project_id: p1.id}, %{project_id: p2.id}]
    })

    [user: user, project1: p1, project2: p2, user_list: user_list]
  end

  test "create trigger with a single target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{slug: "santiment"},
      channel: "telegram",
      operation: %{above: 300.0}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Santiment Absolute price",
        description: "The price goes above $300 or below $200",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with a single non-string target fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: 12,
      channel: "telegram",
      operation: %{above: 300.0}
    }

    assert capture_log(fn ->
             {:error, message} =
               UserTrigger.create_user_trigger(context.user, %{
                 title: "Not a valid signal",
                 is_public: true,
                 settings: trigger_settings
               })

             assert message =~
                      "Trigger structure is invalid. Key `settings` is not valid. Reason: [\"12 is not a valid target\"]"
           end) =~ "UserTrigger struct is not valid. Reason: [\"12 is not a valid target\"]"
  end

  test "create trigger with user_list target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{watchlist_id: context.user_list.id},
      channel: "telegram",
      operation: %{above: 300.0}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Absolute price for a user list",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with lists of slugs target", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{slug: ["santiment", "ethereum", "bitcoin"]},
      channel: "telegram",
      operation: %{above: 300.0}
    }

    {:ok, _trigger} =
      UserTrigger.create_user_trigger(context.user, %{
        title: "Absolute price for a list of slugs",
        is_public: true,
        settings: trigger_settings
      })
  end

  test "create trigger with lists of slugs that contain non-strings fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: ["santiment", "ethereum", "bitcoin", 12],
      channel: "telegram",
      operation: %{above: 300.0}
    }

    capture_log(fn ->
      assert UserTrigger.create_user_trigger(context.user, %{
               title: "Not a valid signal, too",
               is_public: true,
               settings: trigger_settings
             }) ==
               {:error,
                "Trigger structure is invalid. Key `settings` is not valid. Reason: [\"[\\\"santiment\\\", \\\"ethereum\\\", \\\"bitcoin\\\", 12] is not a valid target\"]"}
    end) =~
      ~s/UserTrigger struct is not valid: [{:error, :target, :by, "The target list contains elements that are not string"}]/
  end

  test "non valid target fails", context do
    trigger_settings = %{
      type: "price_absolute_change",
      target: %{watchlist_id: [1, 2, 3]},
      channel: "telegram",
      operation: %{above: 300.0}
    }

    assert capture_log(fn ->
             {:error, message} =
               UserTrigger.create_user_trigger(context.user, %{
                 title: "Yet another not valid settings",
                 is_public: true,
                 settings: trigger_settings
               })

             assert message ==
                      "Trigger structure is invalid. Key `settings` is not valid. Reason: [\"%{watchlist_id: [1, 2, 3]} is not a valid target\"]"
           end) =~
             "UserTrigger struct is not valid. Reason: [\"%{watchlist_id: [1, 2, 3]} is not a valid target\"]"
  end
end
