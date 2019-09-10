defmodule SanbaseWeb.Graphql.ProjectTypes do
  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: Sanbase.Repo

  import Absinthe.Resolution.Helpers

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.{
    ClickhouseResolver,
    ProjectResolver,
    ProjectBalanceResolver,
    ProjectTransactionsResolver,
    IcoResolver,
    TwitterResolver
  }

  alias Sanbase.Model.Project
  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Complexity

  # Includes all available fields
  @desc ~s"""
  A type fully describing a project.
  """
  object :project do
    field :available_metrics, list_of(:string) do
      cache_resolve(&ProjectResolver.available_metrics/3, ttl: 1800)
    end

    field(:id, non_null(:id))
    field(:name, non_null(:string))
    field(:slug, :string)
    field(:ticker, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:email, :string)
    field(:btt_link, :string)
    field(:facebook_link, :string)
    field(:github_link, :string)
    field(:reddit_link, :string)
    field(:twitter_link, :string)
    field(:whitepaper_link, :string)
    field(:blog_link, :string)
    field(:slack_link, :string)
    field(:linkedin_link, :string)
    field(:telegram_link, :string)
    field(:token_address, :string)
    field(:team_token_wallet, :string)
    field(:description, :string)
    field(:long_description, :string)
    field(:token_decimals, :integer)
    field(:main_contract_address, :string)

    field :eth_addresses, list_of(:eth_address) do
      cache_resolve(dataloader(SanbaseRepo))
    end

    field :social_volume_query, :string do
      cache_resolve(
        dataloader(SanbaseRepo, :social_volume_query,
          callback: fn query, project, _args ->
            {:ok, query || Project.SocialVolumeQuery.default_query(project)}
          end
        )
      )
    end

    field :source_slug_mappings, list_of(:source_slug_mapping) do
      cache_resolve(
        dataloader(SanbaseRepo, :source_slug_mappings,
          callback: fn query, _project, _args -> {:ok, query} end
        )
      )
    end

    field :is_trending, :boolean do
      cache_resolve(&ProjectResolver.is_trending/3)
    end

    field :github_links, list_of(:string) do
      cache_resolve(&ProjectResolver.github_links/3)
    end

    field :related_posts, list_of(:post) do
      cache_resolve(&ProjectResolver.related_posts/3)
    end

    field :market_segment, :string do
      cache_resolve(&ProjectResolver.market_segment/3)
    end

    field :infrastructure, :string do
      cache_resolve(&ProjectResolver.infrastructure/3)
    end

    field(:project_transparency, :boolean)

    field :project_transparency_status, :string do
      cache_resolve(&ProjectResolver.project_transparency_status/3)
    end

    field(:project_transparency_description, :string)

    field :eth_balance, :float do
      cache_resolve(&ProjectBalanceResolver.eth_balance/3)
    end

    field :btc_balance, :float do
      cache_resolve(&ProjectBalanceResolver.btc_balance/3)
    end

    field :usd_balance, :float do
      cache_resolve(&ProjectBalanceResolver.usd_balance/3)
    end

    field :funds_raised_icos, list_of(:currency_amount) do
      cache_resolve(&ProjectResolver.funds_raised_icos/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :roi_usd, :decimal do
      cache_resolve(&ProjectResolver.roi_usd/3)
    end

    field :coinmarketcap_id, :string do
      resolve(fn %Project{slug: slug}, _, _ -> {:ok, slug} end)
    end

    field :symbol, :string do
      resolve(&ProjectResolver.symbol/3)
    end

    field :rank, :integer do
      resolve(&ProjectResolver.rank/3)
    end

    field :price_usd, :float do
      resolve(&ProjectResolver.price_usd/3)
    end

    field :price_btc, :float do
      resolve(&ProjectResolver.price_btc/3)
    end

    field :volume_usd, :float do
      resolve(&ProjectResolver.volume_usd/3)
    end

    field :volume_change24h, :float do
      cache_resolve(&ProjectResolver.volume_change_24h/3)
    end

    field :average_dev_activity, :float do
      description("Average dev activity for the last `days` days")
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectResolver.average_dev_activity/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :average_github_activity, :float do
      description("Average github activity for the last `days` days")
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectResolver.average_github_activity/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :twitter_data, :twitter_data do
      cache_resolve(&TwitterResolver.twitter_data/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :marketcap_usd, :float do
      resolve(&ProjectResolver.marketcap_usd/3)
    end

    field :available_supply, :decimal do
      resolve(&ProjectResolver.available_supply/3)
    end

    field :total_supply, :decimal do
      resolve(&ProjectResolver.total_supply/3)
    end

    field :percent_change1h, :decimal do
      resolve(&ProjectResolver.percent_change_1h/3)
    end

    field :percent_change24h, :decimal do
      resolve(&ProjectResolver.percent_change_24h/3)
    end

    field :percent_change7d, :decimal do
      resolve(&ProjectResolver.percent_change_7d/3)
    end

    field :funds_raised_usd_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_usd_ico_end_price/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :funds_raised_eth_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_eth_ico_end_price/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :funds_raised_btc_ico_end_price, :float do
      cache_resolve(&ProjectResolver.funds_raised_btc_ico_end_price/3,
        ttl: 600,
        max_ttl_offset: 600
      )
    end

    field :initial_ico, :ico do
      cache_resolve(&ProjectResolver.initial_ico/3, ttl: 600, max_ttl_offset: 600)
    end

    field(:icos, list_of(:ico), resolve: assoc(:icos))

    field :ico_price, :float do
      cache_resolve(&ProjectResolver.ico_price/3)
    end

    field :signals, list_of(:signal) do
      cache_resolve(&ProjectResolver.signals/3)
    end

    field :price_to_book_ratio, :float do
      cache_resolve(&ProjectResolver.price_to_book_ratio/3)
    end

    @desc "Total ETH spent from the project's team wallets for the last `days`"
    field :eth_spent, :float do
      arg(:days, :integer, default_value: 30)

      cache_resolve(&ProjectTransactionsResolver.eth_spent/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc "ETH spent for each `interval` from the project's team wallet and time period"
    field :eth_spent_over_time, list_of(:eth_spent_data) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)

      cache_resolve(&ProjectTransactionsResolver.eth_spent_over_time/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end

    @desc "Top ETH transactions for project's team wallets"
    field :eth_top_transactions, list_of(:transaction) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:transaction_type, :transaction_type, default_value: :all)
      arg(:limit, :integer, default_value: 10)

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&ProjectTransactionsResolver.eth_top_transactions/3)
    end

    @desc "Top transactions for the token of a given project"
    field :token_top_transactions, list_of(:transaction) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:limit, :integer, default_value: 10)

      complexity(&Complexity.from_to_interval/3)
      cache_resolve(&ProjectTransactionsResolver.token_top_transactions/3)
    end

    @desc "Average daily active addresses for a ERC20 project or Ethereum and given time period"
    field :average_daily_active_addresses, :integer do
      arg(:from, :datetime)
      arg(:to, :datetime)

      cache_resolve(&ClickhouseResolver.average_daily_active_addresses/3,
        ttl: 600,
        max_ttl_offset: 240
      )
    end
  end

  object :source_slug_mapping do
    field(:source, non_null(:string))
    field(:slug, non_null(:string))
  end

  object :eth_address do
    field(:address, non_null(:string))

    field :balance, :float do
      cache_resolve(&ProjectBalanceResolver.eth_address_balance/3)
    end
  end

  object :ico do
    field(:id, non_null(:id))
    field(:start_date, :ecto_date)
    field(:end_date, :ecto_date)
    field(:token_usd_ico_price, :decimal)
    field(:token_eth_ico_price, :decimal)
    field(:token_btc_ico_price, :decimal)
    field(:tokens_issued_at_ico, :decimal)
    field(:tokens_sold_at_ico, :decimal)

    field :funds_raised_usd_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_usd_ico_end_price/3)
    end

    field :funds_raised_eth_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_eth_ico_end_price/3)
    end

    field :funds_raised_btc_ico_end_price, :float do
      resolve(&IcoResolver.funds_raised_btc_ico_end_price/3)
    end

    field(:minimal_cap_amount, :decimal)
    field(:maximal_cap_amount, :decimal)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
    field(:comments, :string)

    field :cap_currency, :string do
      resolve(&IcoResolver.cap_currency/3)
    end

    field :funds_raised, list_of(:currency_amount) do
      resolve(&IcoResolver.funds_raised/3)
    end
  end

  object :ico_with_eth_contract_info do
    field(:id, non_null(:id))
    field(:start_date, :ecto_date)
    field(:end_date, :ecto_date)
    field(:main_contract_address, :string)
    field(:contract_block_number, :integer)
    field(:contract_abi, :string)
  end

  object :currency_amount do
    field(:currency_code, :string)
    field(:amount, :float)
  end

  object :signal do
    field(:name, non_null(:string))
    field(:description, non_null(:string))
  end

  object :eth_spent_data do
    field(:datetime, non_null(:datetime))
    field(:eth_spent, :float)
  end

  object :projects_count do
    field(:erc20_projects_count, non_null(:integer))
    field(:currency_projects_count, non_null(:integer))
    field(:projects_count, non_null(:integer))
  end
end
