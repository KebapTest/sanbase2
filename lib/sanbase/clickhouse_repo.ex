defmodule Sanbase.ClickhouseRepo do
  use Ecto.Repo, otp_app: :sanbase, adapter: ClickhouseEcto

  require Sanbase.Utils.Config, as: Config

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_DATABASE_URL"))

    {:ok, opts}
  end

  defmacro query_transform(query, args) do
    quote bind_quoted: [query: query, args: args] do
      try do
        require Sanbase.ClickhouseRepo, as: ClickhouseRepo

        ordered_params = ClickhouseRepo.order_params(query, args)
        sanitized_query = ClickhouseRepo.sanitize_query(query)

        ClickhouseRepo.query(query, args)
        |> case do
          {:ok, result} ->
            transform_fn = &ClickhouseRepo.load(__MODULE__, {result.columns, &1})

            result =
              Enum.map(
                result.rows,
                transform_fn
              )

            {:ok, result}

          {:error, error} ->
            {:error, error}
        end
      rescue
        e ->
          {:error, "Cannot execute ClickHouse query. Reason: #{Exception.message(e)}"}
      end
    end
  end

  def query_transform(query, args, transform_fn) do
    try do
      ordered_params = order_params(query, args)
      sanitized_query = sanitize_query(query)

      Ecto.Adapters.SQL.query(__MODULE__, sanitized_query, ordered_params)
      |> case do
        {:ok, result} -> {:ok, Enum.map(result.rows, transform_fn)}
        {:error, error} -> {:error, error}
      end
    rescue
      e -> {:error, "Cannot execute ClickHouse query. Reason: #{Exception.message(e)}"}
    end
  end

  def query_reduce(query, args, init, reducer) do
    try do
      ordered_params = order_params(query, args)
      sanitized_query = sanitize_query(query)

      __MODULE__.query(sanitized_query, ordered_params)
      |> case do
        {:ok, result} -> {:ok, Enum.reduce(result.rows, init, reducer)}
        {:error, error} -> {:error, error}
      end
    rescue
      e ->
        {:error, "Cannot execute ClickHouse query. Reason: #{Exception.message(e)}"}
    end
  end

  def sanitize_query(query) do
    query
    |> IO.iodata_to_binary()
    |> String.replace(~r/(\?([0-9]+))(?=(?:[^\\"']|[\\"'][^\\"']*[\\"'])*$)/, "?")
  end

  def order_params(query, params) do
    sanitised =
      Regex.replace(~r/(([^\\]|^))["'].*?[^\\]['"]/, IO.iodata_to_binary(query), "\\g{1}")

    ordering =
      Regex.scan(~r/\?([0-9]+)/, sanitised)
      |> Enum.map(fn [_, x] -> String.to_integer(x) end)

    ordering_count = Enum.max_by(ordering, fn x -> x end, fn -> 0 end)

    if ordering_count != length(params) do
      raise "\nError: number of params received (#{length(params)}) does not match expected (#{
              ordering_count
            })"
    end

    ordered_params =
      ordering
      |> Enum.reduce([], fn ix, acc -> [Enum.at(params, ix - 1) | acc] end)
      |> Enum.reverse()

    case ordered_params do
      [] -> params
      _ -> ordered_params
    end
  end
end
