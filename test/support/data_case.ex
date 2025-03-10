defmodule Sanbase.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Sanbase.DataCase
    end
  end

  setup tags do
    require Sanbase.CaseHelpers

    SanbaseWeb.Graphql.Cache.clear_all()
    Sanbase.Cache.clear_all()
    Sanbase.Price.Validator.clean_state()

    Sanbase.CaseHelpers.checkout_shared(tags)

    product_and_plans = Sanbase.Billing.TestSeed.seed_products_and_plans()

    {:ok,
     product_api: Map.get(product_and_plans, :product_api),
     product_sanbase: Map.get(product_and_plans, :product_sanbase),
     product_sandata: Map.get(product_and_plans, :product_sandata),
     plans: Map.delete(product_and_plans, [:product_api, :product_sanbase, :product_sandata])}
  end

  @doc """
  A helper that transform changeset errors to a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
