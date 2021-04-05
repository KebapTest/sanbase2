defmodule Sanbase.BlockchainAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Infrastructure

  schema "blockchain_addresses" do
    field(:address, :string)
    field(:notes, :string)

    belongs_to(:infrastructure, Infrastructure)
  end

  def changeset(%__MODULE__{} = addr, attrs \\ %{}) do
    addr
    |> cast(attrs, [:address, :infrastructure_id, :notes])
    |> validate_required([:address])
    |> validate_length(:notes, max: 45)
  end

  def by_id(id) do
    case Sanbase.Repo.get(__MODULE__, id) do
      nil -> {:error, "Blockchain address with #{id} does not exist."}
      %__MODULE__{} = addr -> {:ok, addr}
    end
  end

  def by_selector(%{id: id}), do: by_id(id)

  def by_selector(%{infrastructure: infrastructure, address: address}) do
    with {:ok, %{id: infrastructure_id}} <- Sanbase.Model.Infrastructure.by_code(infrastructure),
         {:ok, addr} <-
           maybe_create(%{
             address: address,
             infrastructure_id: infrastructure_id
           }) do
      {:ok, addr}
    end
  end

  @doc ~s"""
  Convert an address to the internal format used in our databases.

  Ethereum addresses are case-insensitive - the upper and lower letters are used
  only for checks. Internally we store the addresses all downcased so they can be
  compared.

  All other chains are sensitive, so they are not changed by this function.
  """
  def to_internal_format(address) do
    case Regex.match?(~r/^0x([A-Fa-f0-9]{40})$/, address) do
      true -> String.downcase(address)
      _ -> address
    end
  end

  def maybe_create(%{address: _, infrastructure_id: _} = attrs) do
    case maybe_create([attrs]) do
      {:ok, [result]} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  def maybe_create(list) when is_list(list) do
    changesets = list |> Enum.map(&changeset(%__MODULE__{}, &1)) |> Enum.with_index()

    Enum.reduce(
      changesets,
      Ecto.Multi.new(),
      fn {changeset, offset}, multi ->
        # notes is an optional field. It should be replaced only if it is in the changeset
        notes_change = if Map.has_key?(changeset.changes, :notes), do: [:notes], else: []
        replace = notes_change ++ [:address, :infrastructure_id]

        multi
        |> Ecto.Multi.insert(offset, changeset,
          on_conflict: {:replace, replace},
          conflict_target: [:address, :infrastructure_id],
          returning: true
        )
      end
    )
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, result} -> {:ok, Map.values(result)}
      {:error, error} -> {:error, error}
    end
  end
end
