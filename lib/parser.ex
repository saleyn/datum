defmodule Parselet do
  @moduledoc """
  Main entry point for parsing text using Parselet components.
  """

  @doc """
  Parses text using the provided components and extracts fields based on their patterns.

  ## Parameters

    * `text` - The text content to parse
    * `components` - A list of component modules that define the fields to extract
    * `merge` - Whether to merge all component fields into a single map (default: `true`).
      When `false`, returns a map with component names as keys and their extracted fields as values.

  ## Returns

  When `merge: true` (default), a map containing all extracted field values merged together.
  Only fields that successfully match their patterns will be included. Fields with `nil` values are excluded.

  When `merge: false`, a map where each key is a component module and each value is a map
  of that component's extracted fields.

  ## Examples

      defmodule MyComponent do
        use Parselet.Component

        field :name, pattern: ~r/Name: (.+)/
        field :age, pattern: ~r/Age: (\\d+)/, transform: &String.to_integer/1
      end

      text = "Name: Alice\\nAge: 30"

      # Merged result (default behavior)
      result = Parselet.parse(text, components: [MyComponent])
      # => %{name: "Alice", age: 30}

      # Nested result
      result = Parselet.parse(text, components: [MyComponent], merge: false)
      # => %{MyComponent => %{name: "Alice", age: 30}}
  """
  def parse(text, opts) do
    components = Keyword.fetch!(opts, :components)
    merge = Keyword.get(opts, :merge, true)
    parse_impl(text, components, merge)
  end

  @doc """
  Parses text using the provided components and raises an error if any required fields are missing.

  This function behaves like `parse/2` but additionally validates that all fields marked
  as `required: true` in the components have been successfully extracted. If any required
  fields are missing, it raises an `ArgumentError`.

  ## Parameters

    * `text` - The text content to parse
    * `components` - A list of component modules that define the fields to extract
    * `merge` - Whether to merge all component fields into a single map (default: `true`)

  ## Returns

  A map containing the extracted field values (merged or nested based on `merge` option),
  or raises `ArgumentError` if required fields are missing.

  ## Examples

      defmodule InvoiceComponent do
        use Parselet.Component

        field :invoice_id, pattern: ~r/Invoice #(\\d+)/, required: true
        field :amount, pattern: ~r/Total: \\$([\\d.]+)/, transform: &String.to_float/1
      end

      # This will succeed
      text = "Invoice #123\\nTotal: $500.00"
      result = Parselet.parse!(text, components: [InvoiceComponent])
      # => %{invoice_id: "123", amount: 500.0}

      # This will raise ArgumentError
      incomplete = "Total: $500.00"
      Parselet.parse!(incomplete, components: [InvoiceComponent])
      # ** (ArgumentError) Missing required fields: [:invoice_id]
  """
  def parse!(text, opts) do
    components = Keyword.fetch!(opts, :components)
    merge = Keyword.get(opts, :merge, true)
    result = parse_impl(text, components, merge)

    all_fields =
      components
      |> Enum.flat_map(fn component ->
        component.__parselet_fields__()
      end)
      |> Enum.into(%{})

    case Parselet.Field.validate_required(result, all_fields, merge) do
      [] -> result
      missing -> raise ArgumentError, "Missing required fields: #{inspect(missing)}"
    end
  end

  defp parse_impl(text, components, true) do
    components
    |> Enum.flat_map(fn component ->
      component.__parselet_fields__()
      |> Enum.map(fn {name, field} ->
        {name, Parselet.Field.extract(field, text)}
      end)
    end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp parse_impl(text, components, false) do
    components
    |> Enum.map(fn component ->
      fields = component.__parselet_fields__()
      |> Enum.map(fn {name, field} ->
        {name, Parselet.Field.extract(field, text)}
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

      {component, fields}
    end)
    |> Enum.into(%{})
  end
end
