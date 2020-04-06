defmodule Sanbase.Auth.Settings do
  use Ecto.Schema
  import Ecto.Changeset

  @newsletter_subscription_types ["DAILY", "WEEKLY", "OFF"]

  embedded_schema do
    field(:hide_privacy_data, :boolean, default: true)
    field(:theme, :string, default: "default")
    field(:page_size, :integer, default: 20)
    field(:is_beta_mode, :boolean, default: false)
    field(:table_columns, :map, default: %{})
    field(:signal_notify_email, :boolean, default: false)
    field(:signal_notify_telegram, :boolean, default: false)
    field(:telegram_chat_id, :integer)
    field(:has_telegram_connected, :boolean, virtual: true)
    field(:newsletter_subscription, :string, default: "OFF")
    field(:newsletter_subscription_updated_at_unix, :integer, default: nil)
    field(:is_promoter, :boolean, default: false)
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [
      :theme,
      :page_size,
      :is_beta_mode,
      :table_columns,
      :signal_notify_email,
      :signal_notify_telegram,
      :telegram_chat_id,
      :hide_privacy_data,
      :is_promoter
    ])
    |> normalize_newsletter_subscription(
      :newsletter_subscription,
      params[:newsletter_subscription]
    )
    |> validate_change(:newsletter_subscription, &validate_subscription_type/2)
  end

  def daily_subscription_type(), do: "DAILY"
  def weekly_subscription_type(), do: "WEEKLY"

  defp normalize_newsletter_subscription(changeset, _field, nil), do: changeset

  defp normalize_newsletter_subscription(changeset, field, value) do
    changeset
    |> put_change(field, value |> Atom.to_string() |> String.upcase())
    |> put_change(
      :newsletter_subscription_updated_at_unix,
      DateTime.utc_now() |> DateTime.to_unix()
    )
  end

  defp validate_subscription_type(_, nil), do: []
  defp validate_subscription_type(_, type) when type in @newsletter_subscription_types, do: []

  defp validate_subscription_type(_, _type) do
    [
      newsletter_subscription:
        "Type not in allowed types: #{inspect(@newsletter_subscription_types)}"
    ]
  end
end
