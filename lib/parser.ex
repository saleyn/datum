defmodule Parselet do
  @moduledoc """
  Main entry point for parsing text using Parselet components.
  """

  @spec parse(String.t(), keyword()) :: map() | struct() | {:error, %{reason: String.t(), fields: [atom()]}}
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

  If required fields are missing or a component `postprocess` hook returns an error, the function returns:
  `{:error, %{reason: String.t(), fields: [atom()]}}`

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

    case parse_impl(text, components, merge, structs_flag) do
      {:error, _} = err -> err
      result ->
        all_fields =
          components
          |> Enum.flat_map(fn component ->
            component.__parselet_fields__()
          end)
          |> Enum.into(%{})

        case Parselet.Field.validate_required(result, all_fields, merge, structs_flag) do
          [] -> result
          missing -> {:error, %{reason: "Missing required fields", fields: missing}}
        end
    end
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

  Raises `ArgumentError` if any required fields are missing or if a component `postprocess` hook returns an error.

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
    case parse(text, opts) do
      {:error, %{reason: reason, fields: fields}} ->
        raise ArgumentError, "#{reason}: #{inspect(fields)}"

      {:error, %{reason: reason}} ->
        raise ArgumentError, reason

      result ->
        result
    end
  end

  defp parse_impl(text, components, merge, structs) do
    case {merge, structs, components} do
      {true, true, [component]} ->
        case parse_impl_flat(text, [component]) do
          {:error, _} = err -> err
          component_fields -> component_to_struct(component, component_fields)
        end

      {_, true, components} when components != [] ->
        components
        |> Enum.reduce_while(%{}, fn component, acc ->
          case parse_impl_flat(text, [component]) do
            {:error, _} = err ->
              {:halt, err}

            fields ->
              {:cont, Map.put(acc, component, component_to_struct(component, fields))}
          end
        end)

      {true, false, _components} ->
        parse_impl_flat(text, components)

      {false, true, components} ->
        components
        |> Enum.reduce_while(%{}, fn component, acc ->
          case parse_impl_flat(text, [component]) do
            {:error, _} = err ->
              {:halt, err}

            fields ->
              {:cont, Map.put(acc, component, component_to_struct(component, fields))}
          end
        end)

      {false, false, _components} ->
        parselet_nested(text, components)
    end
  end

  defp parse_impl_flat(text, components) do
    components
    |> Enum.reduce_while(%{}, fn component, acc ->
      component_text = maybe_preprocess(text, component.__parselet_preprocess__())

      case component.__parselet_fields__()
           |> Enum.map(fn {name, field} ->
             {name, Parselet.Field.extract(field, component_text)}
           end)
           |> Enum.reject(fn {_k, v} -> is_nil(v) end)
           |> Enum.into(%{})
           |> maybe_postprocess(component) do
        {:error, _} = err ->
          {:halt, err}

        fields ->
          {:cont, Map.merge(acc, fields)}
      end
    end)
  end

  defp parselet_nested(text, components) do
    components
    |> Enum.reduce_while(%{}, fn component, acc ->
      component_text = maybe_preprocess(text, component.__parselet_preprocess__())

      case component.__parselet_fields__()
           |> Enum.map(fn {name, field} ->
             {name, Parselet.Field.extract(field, component_text)}
           end)
           |> Enum.reject(fn {_k, v} -> is_nil(v) end)
           |> Enum.into(%{})
           |> maybe_postprocess(component) do
        {:error, _} = err ->
          {:halt, err}

        fields ->
          {:cont, Map.put(acc, component, fields)}
      end
    end)
  end

  defp maybe_preprocess(text, nil), do: text
  defp maybe_preprocess(text, function) when is_function(function, 1), do: function.(text)

  defp maybe_postprocess(fields, component) do
    case component.__parselet_postprocess__() do
      nil -> fields
      function when is_function(function, 1) ->
        case function.(fields) do
          :ok -> fields
          map when is_map(map) -> Map.merge(fields, map)
          {:error, %{reason: reason, fields: fields}} when is_binary(reason) and is_list(fields) ->
            {:error, %{reason: reason, fields: fields}}
          {:error, reason} when is_binary(reason) ->
            {:error, %{reason: reason, fields: []}}
          {:error, reason} ->
            {:error, %{reason: inspect(reason), fields: []}}
          other ->
            raise ArgumentError,
                  "postprocess must return :ok, map, or {:error, reason}, got: #{inspect(other)}"
        end
    end
  end

  defp component_to_struct(component, fields) do
    if function_exported?(component, :__struct__, 0) do
      struct(component, fields)
    else
      Map.put(fields, :__struct__, component)
    end
  end
end
