defmodule Sanbase.Promoters.FirstPromoterApi do
  @moduledoc """
  Wrapper for First Promoter promoters API: https://firstpromoter.com/api/v1/promoters/
  """

  require Logger
  require Sanbase.Utils.Config, as: Config

  alias Sanbase.Auth.User

  @promoters_api_base_url "https://firstpromoter.com/api/v1/promoters/"

  @type promoter_args :: %{
          optional(:ref_id) => String.t(),
          optional(:coupon_code) => String.t()
        }
  @type promoter :: map()

  @spec list() :: {:ok, list(promoter)} | {:error, String.t()}
  def list() do
    do_list(promoters: [], page: 1)
  end

  @spec create(%User{}, promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def create(user, args \\ %{})

  def create(%User{id: id, email: email}, args) do
    data = Map.merge(%{email: email, cust_id: id}, args) |> URI.encode_query()

    Path.join(base_url(), "create")
    |> http_client().post(
      data,
      headers() ++ [{"Content-Type", "application/x-www-form-urlencoded"}]
    )
    |> handle_response()
  end

  def create(_user, _),
    do: {:error, "Can't create promoter account. User doesn't have an email address."}

  @spec show(String.t()) :: {:ok, promoter} | {:error, String.t()}
  def show(user_id) do
    Path.join(base_url(), "show?cust_id=#{user_id}")
    |> http_client().get(headers())
    |> handle_response()
  end

  @spec update(String.t(), promoter_args) :: {:ok, promoter} | {:error, String.t()}
  def update(user_id, args) do
    data = Map.merge(%{cust_id: user_id}, args) |> URI.encode_query()

    Path.join(base_url(), "update")
    |> http_client().put(
      data,
      [{"Content-Type", "application/x-www-form-urlencoded"} | headers()]
    )
    |> handle_response()
  end

  @spec delete(String.t()) :: {:ok, promoter} | {:error, String.t()}
  def delete(user_id) do
    Path.join(base_url(), "delete?cust_id=#{user_id}")
    |> http_client().delete(headers())
    |> handle_response()
  end

  # helpers
  defp do_list(promoters: promoters, page: page) do
    Path.join(base_url(), "list?page=#{page}")
    |> http_client().get(headers())
    |> handle_response()
    |> case do
      {:ok, []} ->
        promoters

      {:ok, new_promoters} ->
        do_list(promoters: promoters ++ new_promoters, page: page + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(response) do
    response
    |> case do
      {:ok, %HTTPoison.Response{status_code: code, body: body}} when code in 200..299 ->
        {:ok, Jason.decode!(body, keys: &atomize_keys/1)}

      other ->
        Logger.error("Error response from first promoter API: #{inspect(filter_response(other))}")
        {:error, "Error response from first promoter API"}
    end
  end

  defp atomize_keys(key) do
    String.to_existing_atom(key)
  rescue
    _ -> String.to_atom(key)
  end

  defp http_client(), do: HTTPoison

  defp base_url, do: @promoters_api_base_url

  defp headers() do
    [
      {"x-api-key", "#{Config.get(:api_key)}"}
    ]
  end

  defp filter_response(
         {:ok, %HTTPoison.Response{request: %HTTPoison.Request{headers: _}} = response}
       ) do
    response
    |> Map.put(:request, Map.put(Map.from_struct(response.request), :headers, "***filtered***"))
  end

  defp filter_response(other), do: other
end
