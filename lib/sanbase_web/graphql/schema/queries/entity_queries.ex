defmodule SanbaseWeb.Graphql.Schema.EntityQueries do
  @moduledoc ~s"""
  Queries and mutations for working with Insights
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth
  alias SanbaseWeb.Graphql.Resolvers.EntityResolver

  object :entity_queries do
    field :get_most_voted, :most_voted_entity_result do
      meta(access: :free)

      arg(:type, :entity_type)
      arg(:types, list_of(:entity_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:current_user_data_only, :boolean, default_value: false)
      arg(:current_user_voted_for_only, :boolean, default_value: false)
      arg(:is_featured_data_only, :boolean, default_value: false)
      arg(:user_role_data_only, :user_role)
      arg(:cursor, :cursor_input_no_order, default_value: nil)
      arg(:filter, :entity_filter)

      arg(:min_title_length, :integer, default_value: 0)
      arg(:min_description_length, :integer, default_value: 0)

      cache_resolve(&EntityResolver.get_most_voted/3,
        ttl: 30,
        max_ttl_offset: 30,
        honor_do_not_cache_flag: true
      )
    end

    field :get_most_recent, :most_recent_entity_result do
      meta(access: :free)

      arg(:type, :entity_type)
      arg(:types, list_of(:entity_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:is_featured_data_only, :boolean, default_value: false)
      arg(:user_role_data_only, :user_role)
      arg(:current_user_data_only, :boolean, default_value: false)
      arg(:cursor, :cursor_input_no_order, default_value: nil)
      arg(:filter, :entity_filter)

      # Set the default values to 3/20. This can be reverted once the
      # frontend sets the limits
      arg(:min_title_length, :integer, default_value: 3)
      arg(:min_description_length, :integer, default_value: 20)

      cache_resolve(&EntityResolver.get_most_recent/3,
        ttl: 30,
        max_ttl_offset: 30,
        honor_do_not_cache_flag: true
      )
    end

    field :get_most_used, :most_used_entity_result do
      meta(access: :free)

      arg(:type, :entity_type)
      arg(:types, list_of(:entity_type))
      arg(:page, :integer)
      arg(:page_size, :integer)
      arg(:is_featured_data_only, :boolean, default_value: false)
      arg(:user_role_data_only, :user_role)
      arg(:cursor, :cursor_input_no_order, default_value: nil)
      arg(:filter, :entity_filter)

      arg(:min_title_length, :integer, default_value: 0)
      arg(:min_description_length, :integer, default_value: 0)

      middleware(JWTAuth)

      cache_resolve(&EntityResolver.get_most_used/3,
        ttl: 30,
        max_ttl_offset: 30,
        honor_do_not_cache_flag: true
      )
    end
  end

  object :entity_mutations do
    field :store_user_entity_interaction, :boolean do
      arg(:entity_type, :entity_type)
      arg(:entity_id, :integer)
      arg(:interaction_type, :entity_interaction_interaction_type)

      middleware(JWTAuth)

      resolve(&EntityResolver.store_user_entity_interaction/3)
    end
  end
end
