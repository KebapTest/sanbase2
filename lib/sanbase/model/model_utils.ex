defmodule Sanbase.Model.ModelUtils do
  def remove_thousands_separator(attrs, key) do
    attrs
    |> Map.get(key)
    |> case do
      nil ->
        attrs

      value ->
        Map.put(attrs, key, String.replace(value, ",", ""))
    end
  end
end
