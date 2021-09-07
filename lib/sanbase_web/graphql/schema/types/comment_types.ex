defmodule SanbaseWeb.Graphql.CommentTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.CommentEntityIdResolver
  alias SanbaseWeb.Graphql.SanbaseRepo

  enum :comment_entity_type_enum do
    value(:blockchain_address)
    value(:chart_configuration)
    value(:insight)
    value(:short_url)
    value(:timeline_event)
    value(:wallet_hunters_proposal)
    value(:watchlist)
  end

  object :comments_feed_item do
    field(:id, non_null(:id))
    field(:insight, :post)
    field(:short_url, :short_url)
    field(:timeline_event, :timeline_event)
    field(:blockchain_address, :blockchain_address_db_stored)

    field(:content, non_null(:string))
    field(:user, non_null(:public_user), resolve: dataloader(SanbaseRepo))
    field(:parent_id, :id)
    field(:root_parent_id, :id)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end

  object :comment do
    field(:id, non_null(:id))

    field :insight_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.insight_id/3)
    end

    field :timeline_event_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.timeline_event_id/3)
    end

    field :blockchain_address_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.blockchain_address_id/3)
    end

    field :proposal_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.proposal_id/3)
    end

    field :watchlist_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.watchlist_id/3)
    end

    field :chart_configuration_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.chart_configuration_id/3)
    end

    field :short_url_id, non_null(:id) do
      cache_resolve(&CommentEntityIdResolver.short_url_id/3)
    end

    field(:content, non_null(:string))
    field(:user, non_null(:public_user), resolve: dataloader(SanbaseRepo))
    field(:parent_id, :id)
    field(:root_parent_id, :id)
    field(:subcomments_count, :integer)
    field(:inserted_at, non_null(:datetime))
    field(:edited_at, :datetime)
  end
end
