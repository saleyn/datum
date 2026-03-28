defmodule Parselet do
  @moduledoc """
  Main entry point for parsing text using Parselet components.
  """

  @spec parse(String.t(), keyword()) :: map() | struct()
  @doc """
  Parses text using the provided components and extracts fields based on their patterns.

  ## Parameters

    * `text` - The text content to parse
    * `components: [module]` - List of component modules that define the fields to extract (returns maps)
    * `structs: [module]` - List of component modules that define the fields to extract (returns structs)
    * `merge` - Whether to merge all component fields into a single map/struct (default: `true`).
      When `false`, returns a map with component names as keys and their extracted values as values.

  ## Returns

  When `merge: true` (default):
  - With `components:`: a map containing all extracted field values merged together
  - With `structs:` and single component: a struct instance with extracted field values
  - With `structs:` and multiple components: a map where each key is a component module and each value is a struct instance

  When `merge: false`:
  - With `components:`: a map where each key is a component module and each value is a map of that component's extracted fields
  - With `structs:`: a map where each key is a component module and each value is a struct instance of that component

  Only fields that successfully match their patterns will be included. Fields with `nil` values are excluded.

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
    {components, structs_flag} =
      case {Keyword.get(opts, :components), Keyword.get(opts, :structs)} do
        {nil, nil} ->
          raise ArgumentError, "must pass either :components or :structs"

        {comps, nil} when is_list(comps) ->
          {comps, false}

        {_, structs} when is_list(structs) ->
          {structs, true}

        {comps, true} when is_list(comps) ->
          {comps, true}

        {comps, false} when is_list(comps) ->
          {comps, false}

        {_, _} ->
          raise ArgumentError, ":components must be a list or :structs must be a list"
      end

    merge = Keyword.get(opts, :merge, true)
    parse_impl(text, components, merge, structs_flag)
  end


  @doc """
  Parses text using the provided components and raises an error if any required fields are missing.

  This function behaves like `parse/2` but additionally validates that all fields marked
  as `required: true` in the components have been successfully extracted. If any required
  fields are missing, it raises an `ArgumentError`.

  ## Parameters

    * `text` - The text content to parse
    * `components: [module]` - List of component modules that define the fields to extract (returns maps)
    * `structs: [module]` - List of component modules that define the fields to extract (returns structs)
    * `merge` - Whether to merge all component fields into a single map/struct (default: `true`).
      When `false`, returns a map with component names as keys and their extracted values as values.

  ## Returns

  When `merge: true` (default):
  - With `components:`: a map containing all extracted field values merged together
  - With `structs:` and single component: a struct instance with extracted field values
  - With `structs:` and multiple components: a map where each key is a component module and each value is a struct instance

  When `merge: false`:
  - With `components:`: a map where each key is a component module and each value is a map of that component's extracted fields
  - With `structs:`: a map where each key is a component module and each value is a struct instance of that component

  Raises `ArgumentError` if any required fields are missing.

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
  @spec parse!(String.t(), keyword()) :: map() | struct()
  def parse!(text, opts) do
    {components, structs_flag} =
      case {Keyword.get(opts, :components), Keyword.get(opts, :structs)} do
        {nil, nil} ->
          raise ArgumentError, "must pass either :components or :structs"

        {comps, nil} when is_list(comps) ->
          {comps, false}

        {_, structs} when is_list(structs) ->
          {structs, true}

        {comps, true} when is_list(comps) ->
          {comps, true}

        {comps, false} when is_list(comps) ->
          {comps, false}

        {_, _} ->
          raise ArgumentError, ":components must be a list or :structs must be a list"
      end

    merge = Keyword.get(opts, :merge, true)
    result = parse_impl(text, components, merge, structs_flag)

    all_fields =
      components
      |> Enum.flat_map(fn component ->
        component.__parselet_fields__()
      end)
      |> Enum.into(%{})

    case Parselet.Field.validate_required(result, all_fields, merge, structs_flag) do
      [] -> result
      missing -> raise ArgumentError, "Missing required fields: #{inspect(missing)}"
    end
  end

  defp parse_impl(text, components, merge, structs) do
    case {merge, structs, components} do
      {true, true, [component]} ->
        component_fields = parse_impl_flat(text, [component])
        component_to_struct(component, component_fields)

      {_, true, components} when components != [] ->
        components
        |> Enum.map(fn component ->
          fields = parse_impl_flat(text, [component])
          {component, component_to_struct(component, fields)}
        end)
        |> Enum.into(%{})

      {true, false, _components} ->
        parse_impl_flat(text, components)

      {false, true, components} ->
        components
        |> Enum.map(fn component ->
          fields = parse_impl_flat(text, [component])
          {component, component_to_struct(component, fields)}
        end)
        |> Enum.into(%{})

      {false, false, _components} ->
        parselet_nested(text, components)
    end
  end

  defp parse_impl_flat(text, components) do
    components
    |> Enum.flat_map(fn component ->
      component_text = maybe_preprocess(text, component.__parselet_preprocess__())

      component.__parselet_fields__()
      |> Enum.map(fn {name, field} ->
        {name, Parselet.Field.extract(field, component_text)}
      end)
    end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  defp parselet_nested(text, components) do
    components
    |> Enum.map(fn component ->
      component_text = maybe_preprocess(text, component.__parselet_preprocess__())

      fields = component.__parselet_fields__()
      |> Enum.map(fn {name, field} ->
        {name, Parselet.Field.extract(field, component_text)}
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

      {component, fields}
    end)
    |> Enum.into(%{})
  end

  defp maybe_preprocess(text, nil), do: text
  defp maybe_preprocess(text, function) when is_function(function, 1), do: function.(text)

  defp component_to_struct(component, fields) do
    if function_exported?(component, :__struct__, 0) do
      struct(component, fields)
    else
      Map.put(fields, :__struct__, component)
    end
  end
end
