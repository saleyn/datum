defmodule Parselet.Field do
  @moduledoc """
  Represents a field definition for text extraction in Parselet components.

  This module defines the structure and behavior of individual fields that can be
  extracted from text using either regex patterns or custom functions.
  """

  @doc """
  Field definition struct for Parselet components.

  ## Fields

    * `name` - The name of the field as an atom (e.g., `:email`, `:phone`)
    * `pattern` - A regex pattern to match against the text. Can be `nil` if using a custom function
    * `capture` - How to capture matched groups. Either `:first` (default) for the first capture group, or `:all` for all capture groups
    * `transform` - A function to transform the captured value. Defaults to identity function (`& &1`)
    * `function` - A custom extraction function that takes the full text and returns the extracted value. Takes precedence over pattern matching
    * `required` - Whether this field must be present in the parsed result. Defaults to `false`
  """
  defstruct [:name, :pattern, :capture, :transform, :function, required: false]

  @doc """
  Creates a new Field struct with the given name and options.

  ## Parameters

    * `name` - The field name as an atom
    * `opts` - Keyword list of options:
      * `:pattern` - Regex pattern for extraction
      * `:capture` - `:first` or `:all` (default: `:first`)
      * `:transform` - Transform function (default: identity)
      * `:function` - Custom extraction function
      * `:required` - Whether field is required (default: `false`)

  ## Examples

      Field.new(:email, pattern: ~r/Email: (.+)/)
      Field.new(:count, pattern: ~r/Items: (\\d+)/, transform: &String.to_integer/1, required: true)
  """
  def new(name, opts) do
    %__MODULE__{
      name: name,
      pattern: Keyword.get(opts, :pattern),
      capture: Keyword.get(opts, :capture, :first),
      transform: Keyword.get(opts, :transform, & &1),
      function: Keyword.get(opts, :function),
      required: Keyword.get(opts, :required, false)
    }
  end

  @doc """
  Extracts a value from text using the field's pattern or custom function.

  ## Parameters

    * `field` - The Field struct containing extraction logic
    * `text` - The text to extract from

  ## Returns

  The extracted and transformed value, or `nil` if extraction fails.
  """
  def extract(%__MODULE__{function: fun}, text) when is_function(fun, 1) do
    fun.(text)
  end

  def extract(%__MODULE__{pattern: nil}, _text), do: nil

  def extract(%__MODULE__{pattern: pattern, capture: :first, transform: t}, text) do
    case Regex.run(pattern, text, capture: :all_but_first) do
      [value] -> t.(value)
      _ -> nil
    end
  end

  def extract(%__MODULE__{pattern: pattern, capture: :all, transform: t}, text) do
    case Regex.run(pattern, text, capture: :all_but_first) do
      values when is_list(values) -> t.(values)
      _ -> nil
    end
  end

  @doc """
  Validates that all required fields are present in the extracted data.

  ## Parameters

    * `fields_map` - Map of extracted field values (merged or nested based on merge option)
    * `fields_struct_map` - Map of field name to Field struct
    * `merge` - Whether the fields_map is merged (true) or nested (false)

  ## Returns

  List of required field names that are missing from the extracted data.
  """
  def validate_required(fields_map, fields_struct_map, true) do
    fields_struct_map
    |> Enum.filter(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
    |> Enum.filter(&(!Map.has_key?(fields_map, &1)))
  end

  def validate_required(fields_map, fields_struct_map, false) do
    # For nested results, we need to check required fields within each component
    fields_struct_map
    |> Enum.filter(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
    |> Enum.filter(fn field_name ->
      # Check if this field exists in any of the component results
      not Enum.any?(Map.values(fields_map), &Map.has_key?(&1, field_name))
    end)
  end

  # Backward compatibility
  def validate_required(fields_map, fields_struct_map) do
    validate_required(fields_map, fields_struct_map, true)
  end
end
