# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

config :ex_admin,
  repo: Sanbase.Repo,
  theme: ExAdmin.Theme.AdminLte2,
  # MyProject.Web for phoenix >= 1.3.0-rc
  module: SanbaseWeb,
  modules: [
    SanbaseWeb.ExAdmin.Dashboard,
    SanbaseWeb.ExAdmin.Statistics,
    SanbaseWeb.ExAdmin.Statistics.UsersWithWatchlist,
    SanbaseWeb.ExAdmin.Statistics.UsersWithMonitoredWatchlist,
    SanbaseWeb.ExAdmin.Statistics.UsersWithDailyNewsletterSubscription,
    SanbaseWeb.ExAdmin.Statistics.UsersWithWeeklyNewsletterSubscription,
    SanbaseWeb.ExAdmin.Model.Project,
    SanbaseWeb.ExAdmin.Widget.ActiveWidget,
    SanbaseWeb.ExAdmin.Chart.Configuration,
    SanbaseWeb.ExAdmin.Model.Project.ContractAddress,
    SanbaseWeb.ExAdmin.Insight.Comment,
    SanbaseWeb.ExAdmin.Model.Currency,
    SanbaseWeb.ExAdmin.Auth.EthAccount,
    SanbaseWeb.ExAdmin.Model.ExchangeAddress,
    SanbaseWeb.ExAdmin.FeaturedItem,
    SanbaseWeb.ExAdmin.Model.Project.GithubOrganization,
    SanbaseWeb.ExAdmin.Signal.HistoricalActivity,
    SanbaseWeb.ExAdmin.Model.Ico,
    SanbaseWeb.ExAdmin.Model.IcoCurrency,
    SanbaseWeb.ExAdmin.Model.Infrastructure,
    SanbaseWeb.ExAdmin.Kafka.KafkaLabelRecord,
    SanbaseWeb.ExAdmin.Model.LatestBtcWalletData,
    SanbaseWeb.ExAdmin.Model.LatestCoinmarketcapData,
    SanbaseWeb.ExAdmin.Model.MarketSegment,
    SanbaseWeb.ExAdmin.Metric.MetricPostgresData,
    SanbaseWeb.ExAdmin.Notifications.Notification,
    SanbaseWeb.ExAdmin.Billing.Plan,
    SanbaseWeb.ExAdmin.SocialData.PopularSearchTerm,
    SanbaseWeb.ExAdmin.Insight.Post,
    SanbaseWeb.ExAdmin.Insight.PostComment,
    SanbaseWeb.ExAdmin.PriceScrapingProgress,
    SanbaseWeb.ExAdmin.Billing.Product,
    SanbaseWeb.ExAdmin.Model.ProjectBtcAddress,
    SanbaseWeb.ExAdmin.Model.ProjectEthAddress,
    SanbaseWeb.ExAdmin.Model.ProjectMarketSegment,
    SanbaseWeb.ExAdmin.Billing.PromoTrial,
    SanbaseWeb.ExAdmin.ScheduleRescrapePrice,
    SanbaseWeb.ExAdmin.Model.Project.SocialVolumeQuery,
    SanbaseWeb.ExAdmin.Model.Project.SourceSlugMapping,
    SanbaseWeb.ExAdmin.Billing.StripeEvent,
    SanbaseWeb.ExAdmin.Billing.Subscription,
    SanbaseWeb.ExAdmin.TableConfiguration,
    SanbaseWeb.ExAdmin.TimelineEvent,
    SanbaseWeb.ExAdmin.Notifications.Type,
    SanbaseWeb.ExAdmin.Auth.User,
    SanbaseWeb.ExAdmin.Auth.UserApikeyToken,
    SanbaseWeb.ExAdmin.Auth.UserRole,
    SanbaseWeb.ExAdmin.UserList,
    SanbaseWeb.ExAdmin.Auth.UserSettings,
    SanbaseWeb.ExAdmin.Signal.UserTrigger,
    SanbaseWeb.ExAdmin.Exchanges.MarketPairMapping,
    SanbaseWeb.ExAdmin.Billing.SignUpTrial,
    SanbaseWeb.ExAdmin.Comments.Notification,
    SanbaseWeb.ExAdmin.Intercom.UserAttributes,
    SanbaseWeb.ExAdmin.Report
  ],
  basic_auth: [
    username: {:system, "ADMIN_BASIC_AUTH_USERNAME"},
    password: {:system, "ADMIN_BASIC_AUTH_PASSWORD"},
    realm: {:system, "ADMIN_BASIC_AUTH_REALM"}
  ]
