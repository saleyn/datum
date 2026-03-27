defmodule Parselet do
  @moduledoc """
  Main entry point for parsing text using Parselet components.
  """

  @doc """
  Parses text using the provided components and extracts fields based on their patterns.

  ## Parameters

    * `text` - The text content to parse
    * `components` - A list of component modules that define the fields to extract

  ## Returns

  A map containing the extracted field values. Only fields that successfully match
  their patterns will be included in the result. Fields with `nil` values are excluded.

  ## Examples

      defmodule MyComponent do
        use Parselet.Component

        field :name, pattern: ~r/Name: (.+)/
        field :age, pattern: ~r/Age: (\\d+)/, transform: &String.to_integer/1
      end

      text = "Name: Alice\\nAge: 30"
      result = Parselet.parse(text, components: [MyComponent])
      # => %{name: "Alice", age: 30}
  """
  def parse(text, components: components) do
    parse_impl(text, components)
  end

  @doc """
  Parses text using the provided components and raises an error if any required fields are missing.

  This function behaves like `parse/2` but additionally validates that all fields marked
  as `required: true` in the components have been successfully extracted. If any required
  fields are missing, it raises an `ArgumentError`.

  ## Parameters

    * `text` - The text content to parse
    * `components` - A list of component modules that define the fields to extract

  ## Returns

  A map containing the extracted field values, or raises `ArgumentError` if required
  fields are missing.

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
  def parse!(text, components: components) do
    result = parse_impl(text, components)

    all_fields =
      components
      |> Enum.flat_map(fn component ->
        component.__parselet_fields__()
      end)
      |> Enum.into(%{})

    case Parselet.Field.validate_required(result, all_fields) do
      [] -> result
      missing -> raise ArgumentError, "Missing required fields: #{inspect(missing)}"
    end
  end

  defp parse_impl(text, components) do
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
end
