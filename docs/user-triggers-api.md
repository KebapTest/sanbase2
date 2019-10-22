# Table of contents

- [Table of contents](#table-of-contents)
  - [Trigger structure](#trigger-structure)
  - [Settings fields](#settings-fields)
  - [Examples](#examples)
    - [Example settings structure for `price_absolute_change`](#example-settings-structure-for-price_absolute_echange)
    - [Example settings structure for `price_percent_change`](#example-settings-structure-for-price_percent_change)
    - [Example settings structure for `daily_active_addresses`](#example-settings-structure-for-daily_active_addresses)
    - [Example settings structure for `trending_words`](#example-settings-structure-for-trending_words)
    - [Example settings structure for `price_volume_difference`](#example-settings-structure-for-price_volume_difference)
    - [Example settings structure for `eth_wallet`](#example-settings-structure-for-eth_wallet)
    - [Example settings structure for `metric_signal`](#example-settings-structure-for-metric_signal)
  - [Create trigger](#create-trigger)
  - [Get all triggers for current user](#get-all-triggers-for-current-user)
  - [Update trigger by id](#update-trigger-by-id)
  - [Remove trigger by id](#remove-trigger-by-id)
  - [Getting trigger by id](#getting-trigger-by-id)
  - [Getting all public triggers](#getting-all-public-triggers)
  - [Getting all public triggers for given user](#getting-all-public-triggers-for-given-user)
  - [Featured user triggers](#featured-user-triggers)
  - [API for signals historical activity (user signals timeline)](#api-for-signals-historical-activity-user-signals-timeline)
    - [Historical activity request](#historical-activity-request)
    - [Historical activity response](#historical-activity-response)

## Trigger structure

These are the fields describing a trigger.

```elixir
    field(:settings, :map) # Each different trigger type has different settings. Described below.
    field(:title, :string) # Trigger title
    field(:description, :string) # Trigger description
    field(:is_public, :boolean, default: false) # Whether trigger is public or private
    field(:cooldown, :string, default: "24h") # After a signal is fired it can be again fired after `cooldown` time has passed. By default - `24h`
    field(:icon_url, :string) # Url of icon for the trigger
    field(:is_active, :boolean, default: true) # Whether trigger is active. By default - yes
    field(:is_repeating, :boolean, default: true) # Whether the signal will fire just one time or it will be working until manually turned off. By default - working until turned off.
```

### Settings fields

- **type** Defines the type of the trigger. Can be one of: `["daily_active_addresses", "price_absolute_change", "price_percent_change", "trending_words", "price_volume_difference"]`
- **target**: Slug or list of slugs or watchlist or ethereum addresses or list of ethereum addresses - `{"slug": "naga"} | {"slug": ["ethereum", "santiment"]} | {"watchlist_id": watchlsit_id} | {"eth_address": "0x123"} | {"eth_address": ["0x123", "0x234"]}`.
- **channel**: `"telegram" | "email"` - Currently notifications are sent only in telegram
- **time_window**: `1d`, `4w`, `1h` - Time string we use throughout the API for `interval`
- **operation** - A map describing the operation that triggers the signal. Check the examples.
- **threshold** - Float threshold used in `price_volume_difference`
- **trigger_time** - At what time of the day to fire the signal. It ISO8601 UTC time used only in `trending_words`, ex: `"12:00:00"`

### Examples

#### Example settings structure for `price_absolute_change`

```json
//price >= 0.51
{
  "type": "price_absolute_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "operation": { "above": 0.51 }
}
```

```json
// price <= 0.50
{
  "type": "price_absolute_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "operation": { "below": 0.5 }
}
```

```json
// price >= 0.49 and price <= 0.51
{
  "type": "price_absolute_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "operation": { "inside_channel": [0.49, 0.51] }
}
```

```json
// price >= 0.49 and price <= 0.51
{
  "type": "price_absolute_change",
  "target": { "slug": ["santiment", "augur"] },
  "channel": "telegram",
  "operation": { "inside_channel": [0.49, 0.51] }
}
```

```json
// price <= 0.49 or price >= 0.51
{
  "type": "price_absolute_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "operation": { "outside_channel": [0.49, 0.51] }
}
```

```json
// price <= 0.98 or price >= 1.02
{
  "type": "price_absolute_change",
  "target": { "slug": ["tether", "dai"] },
  "channel": "telegram",
  "operation": { "outside_channel": [0.98, 1.02] }
}
```

```json
// price <= 0.98 or price >= 1.02. Put the stablecoins watchlist id
// in order to follow all stablecoins
{
  "type": "price_absolute_change",
  "target": { "watchlist_id": 222 },
  "channel": "telegram",
  "operation": { "outside_channel": [0.98, 1.02] }
}
```

#### Example settings structure for `price_percent_change`

```json
// price went up by 10% compared to 1 day ago
{
  "type": "price_percent_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": { "percent_up": 10.0 }
}
```

```json
// price went down by 5% compared to 1 day ago
{
  "type": "price_percent_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": { "percent_down": 5.0 }
}
```

```json
// price went up by 10% OR down by 20% compared to 1 day ago
{
  "type": "price_percent_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": { "some_of": [{ "percent_up": 10.0 }, { "percent_down": 20.0 }] }
}
```

```json
// price did not go up by more than 5% AND did go down by more than 5% compared to 1 day ago
// this is basically implementing inside channel for percentage
{
  "type": "price_percent_change",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": { "none_of": [{ "percent_up": 5.0 }, { "percent_down": 5.0 }] }
}
```

#### Example settings structure for `daily_active_addresses`

```json
// number of daily active addresses increased by 300% compared to the average for the past 30 days
{
  "type": "daily_active_addresses",
  "target": { "slug": ["santiment", "ethereum"] },
  "channel": "telegram",
  "time_window": "30d",
  "operation": { "percent_up": 300.0 }
}
```

```json
// number of daily active addresses decreased by 50% compared to the average for the past 30 days
{
  "type": "daily_active_addresses",
  "target": { "slug": ["santiment", "ethereum"] },
  "channel": "telegram",
  "time_window": "30d",
  "operation": { "percent_down": 50.0 }
}
```

```json
// number of daily active addresses decreased is above 1000
{
  "type": "daily_active_addresses",
  "target": { "slug": ["santiment", "ethereum"] },
  "channel": "telegram",
  "operation": { "above": 1000 }
}
```

```json
// number of daily active addresses decreased is below 100
{
  "type": "daily_active_addresses",
  "target": { "slug": ["santiment", "ethereum"] },
  "channel": "telegram",
  "operation": { "below": 100 }
}
```

```json
// number of daily active addresses decreased is between 100 and 200
{
  "type": "daily_active_addresses",
  "target": { "slug": ["santiment", "ethereum"] },
  "channel": "telegram",
  "operation": { "inside_channel": [100, 200] }
}
```

```json
// number of daily active addresses decreased is below 100 or above 200
{
  "type": "daily_active_addresses",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "operation": { "outside_channel": [100, 200] }
}
```

```json
// daa went up by 100% OR went down by 50%
{
  "type": "daily_active_addresses",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": {
    "some_of": [{ "percent_up": 100.0 }, { "percent_down": 50.0 }]
  }
}
```

```json
// daa went up by 100% AND is above 50
{
  "type": "daily_active_addresses",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": {
    "all_of": [{ "percent_up": 100.0 }, { "above": 50 }]
  }
}
```

```json
// daa did not go up by more than 5% AND did go down by more than 5% compared to 1 day ago
// this is basically implementing inside channel for percent changes
{
  "type": "daily_active_addresses",
  "target": { "slug": "santiment" },
  "channel": "telegram",
  "time_window": "1d",
  "operation": { "none_of": [{ "percent_up": 5.0 }, { "percent_down": 5.0 }] }
}
```

#### Example settings structure for `trending_words`

```json
// Send the list of top 10 currently trending words at 12:00 UTC time.
{
  "type": "trending_words",
  "channel": "telegram",
  "operation": {
    "send_at_predefined_time": true,
    "trigger_time": "12:00:00",
    "size": 10
  }
}
```

```json
// Send a signal if one project is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "trending_project": true }
}
```

```json
// Send a signal if any of the projects is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "slug": ["santiment", "bitcoin"] },
  "operation": { "trending_project": true }
}
```

```json
// Send a signal if any of the projects in a watchlist is trending. A project is trending if
// at least one of its ticker, name or slug is in the trending words
// The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "watchlist_id": 272 },
  "operation": { "trending_project": true }
}
```

```json
// Send a signal if a word is trending. The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "word": "gandalf" },
  "operation": { "trending_word": true }
}
```

```json
// Send a signal if any of the words is trending. The check is case insensitive.
{
  "type": "trending_words",
  "channel": "telegram",
  "target": { "word": ["btc", "eth", "xrp"] },
  "operation": { "trending_word": true }
}
```

#### Example settings structure for `price_volume_difference`

```json
// The price and volume of santiment diverged.
{
  "type": "price_volume_difference",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "threshold": 0.002
}
```

#### Example settings structure for `eth_wallet`

```json
// The combined balance of all santiment's ethereum addresses decreased by 100
{
  "type": "eth_wallet",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "asset": { "slug": "ethereum" },
  "operation": { "amount_down": 100 }
}
```

```json
// The combined balance of all santiment's ethereum addresses increased by 100
{
  "type": "eth_wallet",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "asset": { "slug": "ethereum" },
  "operation": { "amount_up": 200 }
}
```

```json
// The number of santiment tokens in the address 0x123 increased by 1000
{
  "type": "eth_wallet",
  "channel": "telegram",
  "target": { "eth_address": "0x123" },
  "asset": { "slug": "santiment" },
  "operation": { "amount_up": 1000 }
}
```

#### Example settings structure for `metric_signal`

```json
// The MVRV of Santiment's project is above 2
{
  "type": "metric_signal",
  "metric": "mvrv_usd",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "above": 2 }
}
```

```json
// The Circulation of Santiment's tokens increased by 10% compared to 1 day ago
{
  "type": "metric_signal",
  "metric": "circulation_1d",
  "time_window": "1d",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "percent_up": 10 }
}
```

```json
// The Exchange Inflow of Santiment's project increased by 10% AND is above 10_000
{
  "type": "metric_signal",
  "metric": "exchange_inflow",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "all_of": [{ "percent_up": 10 }, { "above": 10000 }] }
}
```

```json
// The Exchange Outflow of Santiment's project increased by 10% OR is above 10_000
{
  "type": "metric_signal",
  "metric": "exchange_outflow",
  "channel": "telegram",
  "target": { "slug": "santiment" },
  "operation": { "some_of": [{ "percent_up": 10 }, { "above": 10000 }] }
}
```

### Create trigger

```graphql
mutation {
  createTrigger(
    title: "test ceco"
    settings: "{\"channel\":\"telegram\",\"operation\":{\"percent_up\": 200},\"target\":{\"slug\": \"santiment\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  ) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Get all triggers for current user

```graphql
{
  currentUser {
    id
    triggers {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Update trigger by id

- If `settings` is updated all fields in settings must be provided.
- Trigger top-level ields can be updated - for ex: `isPublic`.

Update `settings` and `isPublic`.

```graphql
mutation {
  updateTrigger(
    id: 16
    isPublic: true
    settings: "{\"channel\":\"telegram\",\"operation\":{\"percent_up\": 250},\"target\":{\"slug\": \"santiment\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  ) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

Update only trigger top-level field `isPublic`.

```graphql
mutation {
  updateTrigger(id: 16, isPublic: true) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Remove trigger by id

```graphql
mutation {
  removeTrigger(id: 9) {
    trigger {
      id
    }
  }
}
```

### Getting trigger by id

```graphql
{
  getTriggerById(id: 16) {
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Getting all public triggers

```graphql
{
  allPublicTriggers {
    userId
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Getting all public triggers for given user

```graphql
{
  publicTriggersForUser(userId: 31) {
    userId
    trigger {
      id
      title
      description
      isPublic
      cooldown
      iconUrl
      isActive
      isRepeating
      settings
    }
  }
}
```

### Featured user triggers

```graphql
{
  featuredUserTriggers {
    trigger {
      title
      settings
    }
  }
}
```

### API for signals historical activity (user signals timeline)

#### Historical activity request

```graphql
{
  signalsHistoricalActivity(
    limit: 1
    cursor: { type: BEFORE, datetime: "2019-03-11T11:56:42.970284" }
  ) {
    cursor {
      before
      after
    }
    activity {
      payload
      triggeredAt
      trigger {
        id
        title
        description
      }
    }
  }
}
```

#### Historical activity response

````graphql
{
  "data": {
    "signalsHistoricalActivity": {
      "activity": [
        {
          "payload": {
            "all": "Trending words for: `2019-03-11`\n\n```\nWord    | Score\n------- | -------\ntheta   | 704\nxlm     | 425\nqlc     | 224\nnxs     | 210\nmining  | 207\nnano    | 196\nherpes  | 178\nxrp     | 178\nasic    | 152\ntattoos | 128\n```\nMore info: http://localhost:4000/sonar\n"
          },
          "triggeredAt": "2019-03-11T11:56:41.970284Z",
          "trigger": {
            "id": 5,
            "description": null,
            "title": "alabala",
            ...
          }
        }
      ],
      "cursor": {
        "after": "2019-03-11T11:56:41.970284Z",
        "before": "2019-03-11T11:56:41.970284Z"
      }
    }
  }
}
````

- `payload` is a json with key `slug` | `all` (when there is no specific slug) and value markdown message.

#### Take activities newer than certain datetime

```graphql
    signalsHistoricalActivity(
      limit:1,
      cursor:{
        type:AFTER,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

#### Take activities before certain datetime

```graphql
    signalsHistoricalActivity(
      limit:1,
      cursor:{
        type:BEFORE,
        datetime:"2019-03-11T11:56:42.970284Z"
      }
    )
```

### Historical trigger points

Takes currently filled settings and a chosen cooldown and calculates historical trigger points that can be used in a preview chart.

- Daily Active Addresses - 90 days of historical data. Minimal `time_window` is 2 days because intervals are 1 day each.
- Price - percent and absolute - 90 days of data. Minimal `time_window` is 2 hours because intervals are 1 hour each.
- PriceVolumeDifference - 180 days of data.

```graphql
{
  historicalTriggerPoints(
    cooldown: "2d"
    settings: "{\"operation\":{\"percent_up\": 200},\"target\":{\"slug\": \"naga\"},\"time_window\":\"30d\",\"type\":\"daily_active_addresses\"}"
  )
}
```

```graphql
{
  "data": {
    "historicalTriggerPoints": [
      {
        "active_addresses": 16,
        "datetime": "2018-12-18T00:00:00Z",
        "percent_change": 0,
        "price": 0.11502404063688457,
        "triggered?": false
      },
      {
        "active_addresses": 15,
        "datetime": "2018-12-19T00:00:00Z",
        "percent_change": 0,
        "price": 0.1267324715437431,
        "triggered?": false
      },
      {
        "active_addresses": 17,
        "datetime": "2018-12-20T00:00:00Z",
        "percent_change": 0,
        "price": 0.12995444389604163,
        "triggered?": false
      },
      ...
```
