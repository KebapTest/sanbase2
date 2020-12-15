defmodule Sanbase.Auth.User do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Auth.{
    User,
    EthAccount,
    UserApikeyToken,
    UserSettings
  }

  alias Sanbase.Vote
  alias Sanbase.Insight.Post
  alias Sanbase.UserList
  alias Sanbase.Repo
  alias Sanbase.Telegram
  alias Sanbase.Signal.HistoricalActivity
  alias Sanbase.Auth.UserFollower
  alias Sanbase.Billing.Subscription

  @salt_length 64
  @email_token_length 64

  # Fallback username and email for Insights owned by deleted user accounts
  @anonymous_user_username "anonymous"
  @anonymous_user_email "anonymous@santiment.net"

  # User with free subscription that is used for external integration testing
  @sanbase_bot_email "sanbase.bot@santiment.net"

  @derive {Inspect,
           except: [
             :salt,
             :email_token,
             :email_token_generated_at,
             :email_token_validated_at,
             :email_candidate_token,
             :email_candidate_token_generated_at,
             :email_candidate_token_validated_at,
             :consent_id
           ]}

  schema "users" do
    field(:email, :string)
    field(:email_candidate, :string)
    field(:username, :string)
    field(:salt, :string)
    field(:san_balance, :decimal)
    field(:san_balance_updated_at, :naive_datetime)
    field(:email_token, :string)
    field(:email_token_generated_at, :naive_datetime)
    field(:email_token_validated_at, :naive_datetime)
    field(:email_candidate_token, :string)
    field(:email_candidate_token_generated_at, :naive_datetime)
    field(:email_candidate_token_validated_at, :naive_datetime)
    field(:consent_id, :string)
    field(:test_san_balance, :decimal)
    field(:stripe_customer_id, :string)
    field(:first_login, :boolean, default: false, virtual: true)
    field(:avatar_url, :string)
    field(:is_registered, :boolean, default: false)
    field(:is_superuser, :boolean, default: false)
    field(:twitter_id, :string)

    # GDPR related fields
    field(:privacy_policy_accepted, :boolean, default: false)
    field(:marketing_accepted, :boolean, default: false)

    has_one(:telegram_user_tokens, Telegram.UserToken, on_delete: :delete_all)
    has_one(:sign_up_trial, Sanbase.Billing.Subscription.SignUpTrial, on_delete: :delete_all)
    has_many(:timeline_events, Sanbase.Timeline.TimelineEvent, on_delete: :delete_all)
    has_many(:eth_accounts, EthAccount, on_delete: :delete_all)
    has_many(:votes, Vote, on_delete: :delete_all)
    has_many(:apikey_tokens, UserApikeyToken, on_delete: :delete_all)
    has_many(:user_lists, UserList, on_delete: :delete_all)
    has_many(:posts, Post, on_delete: :delete_all)
    has_many(:signals_historical_activity, HistoricalActivity, on_delete: :delete_all)
    has_many(:followers, UserFollower, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:following, UserFollower, foreign_key: :follower_id, on_delete: :delete_all)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
    has_many(:roles, {"user_roles", Sanbase.Auth.UserRole}, on_delete: :delete_all)
    has_many(:promo_trials, Sanbase.Billing.Subscription.PromoTrial, on_delete: :delete_all)
    has_many(:triggers, Sanbase.Signal.UserTrigger, on_delete: :delete_all)
    has_many(:chart_configurations, Sanbase.Chart.Configuration, on_delete: :delete_all)

    has_one(:user_settings, UserSettings, on_delete: :delete_all)

    timestamps()
  end

  def get_unique_str(%__MODULE__{} = user) do
    user.email || user.username || user.twitter_id || "id_#{user.id}"
  end

  def describe(%__MODULE__{} = user) do
    cond do
      user.username != nil -> "User with username #{user.username}"
      user.email != nil -> "User with email #{user.email}"
      user.twitter_id != nil -> "User with twitter_id #{user.twitter_id}"
      true -> "User with id #{user.id}"
    end
  end

  def generate_salt() do
    :crypto.strong_rand_bytes(@salt_length) |> Base.url_encode64() |> binary_part(0, @salt_length)
  end

  def generate_email_token() do
    :crypto.strong_rand_bytes(@email_token_length) |> Base.url_encode64()
  end

  def changeset(%User{} = user, attrs \\ %{}) do
    attrs = Sanbase.DateTimeUtils.truncate_datetimes(attrs)

    user
    |> cast(attrs, [
      :avatar_url,
      :consent_id,
      :email_candidate_token_generated_at,
      :email_candidate_token_validated_at,
      :email_candidate_token,
      :email_candidate,
      :email_token_generated_at,
      :email_token_validated_at,
      :email_token,
      :email,
      :first_login,
      :is_registered,
      :is_superuser,
      :marketing_accepted,
      :privacy_policy_accepted,
      :salt,
      :stripe_customer_id,
      :test_san_balance,
      :twitter_id,
      :username
    ])
    |> normalize_username(attrs)
    |> normalize_email(attrs[:email], :email)
    |> normalize_email(attrs[:email_candidate], :email_candidate)
    |> validate_change(:username, &validate_username_change/2)
    |> validate_change(:email_candidate, &validate_email_candidate_change/2)
    |> validate_change(:avatar_url, &validate_url_change/2)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:stripe_customer_id)
    |> unique_constraint(:twitter_id)
  end

  # Email functions
  defdelegate find_by_email_candidate(candidate, token), to: __MODULE__.Email
  defdelegate update_email_token(user, consent \\ nil), to: __MODULE__.Email
  defdelegate update_email_candidate(user, candidate), to: __MODULE__.Email
  defdelegate mark_email_token_as_validated(user), to: __MODULE__.Email
  defdelegate update_email_from_email_candidate(user), to: __MODULE__.Email
  defdelegate email_token_valid?(user, token), to: __MODULE__.Email
  defdelegate email_candidate_token_valid?(user, candidate_token), to: __MODULE__.Email
  defdelegate send_login_email(user, origin_url, args \\ %{}), to: __MODULE__.Email
  defdelegate send_verify_email(user), to: __MODULE__.Email

  # San Balance functions

  defdelegate san_balance_cache_stale?(user), to: __MODULE__.SanBalance
  defdelegate update_san_balance_changeset(user), to: __MODULE__.SanBalance
  defdelegate san_balance(user), to: __MODULE__.SanBalance
  defdelegate san_balance!(user), to: __MODULE__.SanBalance

  def by_id(user_id) when is_integer(user_id) do
    case Sanbase.Repo.get_by(User, id: user_id) do
      nil ->
        {:error, "Cannot fetch the user with id #{user_id}"}

      user ->
        {:ok, user}
    end
  end

  def by_id(user_ids) when is_list(user_ids) do
    users =
      from(
        u in __MODULE__,
        where: u.id in ^user_ids,
        order_by: fragment("array_position(?, ?::int)", ^user_ids, u.id)
      )
      |> Repo.all()

    {:ok, users}
  end

  def by_email(email) when is_binary(email) do
    Sanbase.Repo.get_by(User, email: email)
  end

  def by_selector(%{id: id}), do: Repo.get_by(__MODULE__, id: id)
  def by_selector(%{email: email}), do: Repo.get_by(__MODULE__, email: email)
  def by_selector(%{username: username}), do: Repo.get_by(__MODULE__, username: username)

  def update_field(%__MODULE__{} = user, field, value) do
    case Map.fetch!(user, field) == value do
      true ->
        {:ok, user}

      false ->
        user |> changeset(%{field => value}) |> Repo.update()
    end
  end

  def find_or_insert_by(field, value, attrs \\ %{})
      when field in [:email, :username, :twitter_id] do
    case Repo.get_by(User, [{field, value}]) do
      nil ->
        user_create_attrs =
          Map.merge(
            attrs,
            %{field => value, salt: User.generate_salt(), first_login: true}
          )

        %User{}
        |> User.changeset(user_create_attrs)
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  def ascii_username?(nil), do: true

  def ascii_username?(username) do
    username
    |> String.to_charlist()
    |> List.ascii_printable?()
  end

  defp normalize_username(changeset, %{username: username}) when not is_nil(username) do
    put_change(changeset, :username, String.trim(username))
  end

  defp normalize_username(changeset, _), do: changeset

  defp normalize_email(changeset, nil, _), do: changeset

  defp normalize_email(changeset, email, field) do
    email =
      email
      |> String.downcase()
      |> String.trim()

    put_change(changeset, field, email)
  end

  defp validate_username_change(_, username) do
    if ascii_username?(username) do
      []
    else
      [username: "Username can contain only latin letters and numbers"]
    end
  end

  defp validate_email_candidate_change(_, email_candidate) do
    if Repo.get_by(User, email: email_candidate) do
      [email: "Email has already been taken"]
    else
      []
    end
  end

  defp validate_url_change(_, url) do
    case Sanbase.Validation.valid_url?(url) do
      :ok -> []
      {:error, msg} -> [avatar_url: msg]
    end
  end

  def change_username(%__MODULE__{username: username} = user, username), do: {:ok, user}

  def change_username(%__MODULE__{} = user, username) do
    user
    |> changeset(%{username: username})
    |> Repo.update()
  end

  @spec add_eth_account(%User{}, String.t()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def add_eth_account(%User{id: user_id}, address) do
    EthAccount.changeset(%EthAccount{}, %{user_id: user_id, address: address})
    |> Repo.insert()
  end

  @doc ~s"""
  An EthAccount can be removed only if there is another mean to login - an email address
  or another ethereum address set. If the address that is being removed is the only
  address and there is no email, the user account will be lost as there won't be
  any way to log in
  """
  @spec remove_eth_account(%User{}, String.t()) :: true | {:error, String.t()}
  def remove_eth_account(%User{id: user_id} = user, address) do
    if can_remove_eth_account?(user, address) do
      from(
        ea in EthAccount,
        where: ea.user_id == ^user_id and ea.address == ^address
      )
      |> Repo.delete_all()
      |> case do
        {1, _} -> true
        {0, _} -> {:error, "Address #{address} does not exist or is not owned by user #{user_id}"}
      end
    else
      {:error,
       "Cannot remove ethereum address #{address}. There must be an email or other ethereum address set."}
    end
  end

  def anonymous_user_username, do: @anonymous_user_username
  def anonymous_user_email, do: @anonymous_user_email

  def anonymous_user_id() do
    Repo.get_by(__MODULE__, email: @anonymous_user_email, username: @anonymous_user_username)
    |> Map.get(:id)
  end

  def sanbase_bot_email, do: @sanbase_bot_email
  def sanbase_bot_email(idx), do: String.replace(@sanbase_bot_email, "@", "#{idx}@")

  def has_credit_card_in_stripe?(user_id) do
    with {:ok, user} <- by_id(user_id),
         {:ok, customer} <- Sanbase.StripeApi.retrieve_customer(user) do
      customer.default_source != nil
    else
      _ -> false
    end
  end

  def update_avatar_url(%User{} = user, avatar_url) do
    user
    |> changeset(%{avatar_url: avatar_url})
    |> Repo.update()
  end

  defp can_remove_eth_account?(%User{id: user_id, email: email}, address) do
    count_other_accounts =
      from(ea in EthAccount,
        where: ea.user_id == ^user_id and ea.address != ^address
      )
      |> Repo.aggregate(:count, :id)

    count_other_accounts > 0 or not is_nil(email)
  end
end
