# Parselet API Documentation

## Overview

Parselet is a declarative text parsing library that extracts structured data from unstructured text. The library provides three main modules:

1. **`Parselet`** - Entry point for parsing operations
2. **`Parselet.Component`** - DSL for defining extraction components
3. **`Parselet.Field`** - Field extraction and transformation logic

---

## Module: `Parselet`

Main entry point for parsing text using Parselet components.

### Functions

#### `parse(text, components: components_list | structs: structs_list)`

Extracts data from text using the specified components, with support for map or struct output.

**Signature:**
```elixir
@spec parse(String.t(), keyword()) :: map() | struct()
```

**Parameters:**
- `text` (`String.t`) - The text to parse
- `components: [module]` - List of component modules (created with `use Parselet.Component`)
- `structs: [module]` - List of component modules to return as struct(s)
- `merge` (`boolean`, default `true`) - Whether to merge component fields into one map/struct (`false` for nested per-component map/struct)

**Returns:** `map()` or `struct()` - Parsed result

**Behavior:**
- Iterates through all components and their defined fields
- Calls `Parselet.Field.extract/2` for each field
- Filters out fields that didn't match (nil values)
- With `components`, returns a map of merged values (`merge: true`) or nested component maps (`merge: false`)
- With `structs`, returns a struct for single component, or map of component module to struct for multiple components, with same merge/non-merge semantics

**Example:**

```elixir
defmodule MyParser do
  use Parselet.Component
  
  field :name, pattern: ~r/Name:\s*(.+)/
  field :email, pattern: ~r/Email:\s*(.+)/
end

text = "Name: Alice\nEmail: alice@example.com"
result = Parselet.parse(text, components: [MyParser])
# => %{name: "Alice", email: "alice@example.com"}
```

**Multiple Components:**

```elixir
result = Parselet.parse(text, components: [
  MyApp.Parselet.Parser1,
  MyApp.Parselet.Parser2
])
# Fields from both components are merged
```

#### `parse!(text, components: components_list | structs: structs_list)`

Extracts data from text with validation of required fields.

**Signature:**
```elixir
@spec parse!(String.t(), keyword()) :: map() | struct() | no_return()
```

**Parameters:**
- `text` (`String.t`) - The text to parse
- `components: [module]` - List of component modules
- `structs: [module]` - List of component modules for struct output
- `merge` (`boolean`, default `true`) - Whether to merge component fields into one map/struct (`false` for nested per-component map/struct)

**Returns:** `map()` - Map containing extracted fields

**Raises:** `ArgumentError` - If any required fields are missing

**Example:**

```elixir
defmodule MyParser do
  use Parselet.Component
  
  field :name, pattern: ~r/Name:\s*(.+)/, required: true
  field :email, pattern: ~r/Email:\s*(.+)/
end

text = "Name: Alice"

# This will raise because :name is present but :email would be optional
result = Parselet.parse!(text, components: [MyParser])
# => %{name: "Alice"}

# If we try with missing required field:
text = "Email: alice@example.com"
Parselet.parse!(text, components: [MyParser])
# => raises ArgumentError: Missing required fields: [:name]
```

---

## Module: `Parselet.Component`

DSL for defining text extraction components.

### Macros

#### `field(name, opts)`

Defines a field to extract from text.

**Signature:**
```elixir
defmacro field(name, opts)
```

**Parameters:**
- `name` (atom) - Field name in the result map
- `opts` (keyword list) - Field extraction options

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:pattern` | `Regex.t` | `nil` | Regex pattern to match and capture data |
| `:capture` | atom | `:first` | How to capture: `:first` or `:all` |
| `:transform` | function | `& &1` | Function to transform captured value |
| `:function` | function | `nil` | Custom extraction function (alternative to `:pattern`) |
| `:required` | boolean | `false` | Mark field as required (use with `parse!/2`) |

**Pattern-based Extraction:**

```elixir
# Single capture group
field :reservation_code,
  pattern: ~r/Code:\s*([A-Z0-9]+)/,
  capture: :first

# Multiple capture groups
field :date_parts,
  pattern: ~r/Date:\s*(\d{4})-(\d{2})-(\d{2})/,
  capture: :all

# With transformation
field :count,
  pattern: ~r/Total:\s*(\d+)/,
  capture: :first,
  transform: &String.to_integer/1
```

**Function-based Extraction:**

```elixir
# Custom extraction logic
field :summary,
  function: fn text ->
    text
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, "Summary"))
  end

# Can use captured groups from pattern with transform
field :price,
  pattern: ~r/\$(\d+\.\d{2})/,
  capture: :first,
  transform: fn amount ->
    amount
    |> String.replace(",", "")
    |> String.to_float()
  end

# Mark field as required
field :account_id,
  pattern: ~r/ID:\s*([A-Z0-9]+)/,
  capture: :first,
  required: true
```

**Behavior:**
- Compile-time macro that registers field definitions
- Fields are stored in `@parselet_fields` attribute
- At module compilation, `__before_compile__/1` generates `__parselet_fields__/0` function
- This function returns a map of field name → `Parselet.Field` struct

---

## Module: `Parselet.Field`

Handles field extraction and value transformation.

### Struct

```elixir
defstruct [
  :name,           # atom - field name
  :pattern,        # Regex.t or nil - regex pattern
  :capture,        # :first or :all - capture strategy
  :transform,      # function - transformation function
  :function,       # function or nil - custom extraction function
  required: false  # boolean - whether field is required
]
```

### Functions

#### `new(name, opts)`

Creates a new Field struct from options.

**Signature:**
```elixir
@spec new(atom(), keyword()) :: t()
```

**Parameters:**
- `name` (atom) - Field name
- `opts` (keyword list) - Field options (pattern, capture, transform, function)

**Returns:** `%Parselet.Field{}` - Field struct

**Example:**

```elixir
field = Parselet.Field.new(:email, pattern: ~r/Email:\s*(\S+)/, capture: :first)
```

#### `extract(field, text)`

Extracts data from text using the field definition.

**Signature:**
```elixir
@spec extract(t(), String.t()) :: any() | nil
```

**Parameters:**
- `field` (`Parselet.Field.t`) - Field struct with extraction rules
- `text` (`String.t`) - Text to extract from

**Returns:** Extracted and transformed value, or `nil` if not found

#### `validate_required(result_map, fields_struct_map)`

Validates that all required fields are present in the result.

**Signature:**
```elixir
@spec validate_required(map(), map()) :: [atom()]
```

**Parameters:**
- `result_map` (`map`) - Parsed result from extraction
- `fields_struct_map` (`map`) - Map of field_name → `Parselet.Field` struct

**Returns:** List of missing required field names (empty list if all required fields present)

**Example:**

```elixir
# Get all fields from a component
fields = MyComponent.__parselet_fields__()

# Parse text
result = Parselet.Field.extract(field, text)

# Check for missing required fields
missing = Parselet.Field.validate_required(result, fields)

case missing do
  [] -> {:ok, result}
  _ -> {:error, "Missing fields: #{inspect(missing)}"}
end
```

**Extraction Logic:**

1. **If `:function` is defined:** Calls the function with the text and returns result
   ```elixir
   extract(%Field{function: fn text -> parse_text(text) end}, text)
   # => parse_text(text)
   ```

2. **If `:pattern` is nil:** Returns nil
   ```elixir
   extract(%Field{pattern: nil}, text)
   # => nil
   ```

3. **If `:capture` is `:first`:** Extracts first capture group and transforms
   ```elixir
   extract(%Field{pattern: ~r/Value:\s*(\d+)/, capture: :first, transform: &String.to_integer/1}, text)
   # => Returns transformed first capture group or nil
   ```

4. **If `:capture` is `:all`:** Extracts all capture groups and transforms
   ```elixir
   extract(%Field{pattern: ~r/(\d{4})-(\d{2})-(\d{2})/, capture: :all, transform: &join_date/1}, text)
   # => Returns transformed list of capture groups or nil
   ```

**Examples:**

```elixir
# Pattern extraction with first capture
field = Parselet.Field.new(:name, pattern: ~r/Name:\s*(.+)/, capture: :first)
result = Parselet.Field.extract(field, "Name: Alice")
# => "Alice"

# Multiple captures
field = Parselet.Field.new(:date, 
  pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,
  capture: :all,
  transform: fn [y, m, d] -> "#{y}/#{m}/#{d}" end
)
result = Parselet.Field.extract(field, "Date: 2026-03-27")
# => "2026/03/27"

# Custom function
field = Parselet.Field.new(:lines, 
  function: fn text -> String.split(text, "\n") end
)
result = Parselet.Field.extract(field, "line1\nline2")
# => ["line1", "line2"]

# No match returns nil
field = Parselet.Field.new(:missing, pattern: ~r/NotFound:\s*(.+)/)
result = Parselet.Field.extract(field, "Some text")
# => nil
```

---

## Component Structure

When you use `Parselet.Component`, your module gets:

1. **`@parselet_fields` attribute** - Accumulates field definitions during compilation
2. **`__parselet_fields__/0` function** - Generated automatically, returns map of fields
3. **`field/2` macro** - DSL for defining fields

**Generated code example:**

```elixir
defmodule MyParser do
  use Parselet.Component

  field :name, pattern: ~r/Name:\s*(.+)/
  field :email, pattern: ~r/Email:\s*(.+)/
end

# Generates:
# def __parselet_fields__() do
#   %{
#     name: %Parselet.Field{name: :name, pattern: ~r/Name:\s*(.+)/, ...},
#     email: %Parselet.Field{name: :email, pattern: ~r/Email:\s*(.+)/, ...}
#   }
# end
```

---

## Data Flow Diagram

```
Parselet.parse(text, components: [MyComponent])
    ↓
For each component:
  For each field in __parselet_fields__:
    Parselet.Field.extract(field, text)
      ↓
    Check if :function is defined
      ↓ Yes: Call function(text), return result
      ↓ No: Check if :pattern is nil
             ↓ Yes: Return nil
             ↓ No: Run Regex.run with pattern
                   ↓
                   If :capture is :first:
                     Get first capture group, apply :transform
                   If :capture is :all:
                     Get all capture groups, apply :transform
                   ↓ No match: Return nil
    ↓
Collect all non-nil results
    ↓
Return as map: %{field_name: value, ...}
```

---

## Error Handling

Parselet uses Elixir's pattern matching and optional field extraction:

```elixir
# Fields that don't match simply won't appear in the result
result = Parselet.parse(text, components: [MyComponent])

# Safe access with Map.get/3
name = Map.get(result, :name, "Unknown")

# Pattern matching with defaults
%{name: name, email: email} = Map.merge(result, %{name: nil, email: nil})
```

**Transform Errors:**

If a transform function raises an error, it propagates:

```elixir
# This will raise if the captured value can't be converted to integer
field :count,
  pattern: ~r/Count:\s*(\w+)/,
  capture: :first,
  transform: &String.to_integer/1
# => If pattern matches "abc", String.to_integer/1 raises
```

---

## Performance Notes

- **Regex Compilation:** Patterns are compiled at compile-time, no runtime cost
- **Field Registration:** Fields are metadata, minimal overhead
- **Transform Functions:** Only called for matched fields
- **Component Merging:** Results from multiple components are merged, no conflicts if field names differ

---

## Common Recipes

### Optional Fields

```elixir
field :optional_email,
  pattern: ~r/Email:\s*(.+)/,
  capture: :first

# In usage:
result = Parselet.parse(text, components: [MyComponent])
email = Map.get(result, :optional_email)  # nil if not found
```

### Conditional Extraction

```elixir
# Extract different patterns based on content
field :value,
  function: fn text ->
    cond do
      String.contains?(text, "USD") -> extract_usd(text)
      String.contains?(text, "EUR") -> extract_eur(text)
      true -> nil
    end
  end
```

### Nested Data

```elixir
# Extract and parse as nested structure
field :contact,
  function: fn text ->
    %{
      name: extract_name(text),
      email: extract_email(text),
      phone: extract_phone(text)
    }
  end
```

### Chained Transformations

```elixir
field :formatted_date,
  pattern: ~r/Date:\s*(.+)/,
  capture: :first,
  transform: fn date_str ->
    date_str
    |> String.trim()
    |> Date.from_iso8601!()
    |> Calendar.strftime("%B %d, %Y")
  end
```

---

## Type Specifications

While Parselet doesn't use explicit @spec annotations in the current version, here are the expected types:

```elixir
# Parselet module
@spec parse(String.t(), components: [module()]) :: map()

# Parselet.Field module  
@spec new(atom(), keyword()) :: %Parselet.Field{}
@spec extract(%Parselet.Field{}, String.t()) :: any() | nil

# Transform function signature
@type transform_fn :: (any() -> any())

# Extraction function signature  
@type extractor_fn :: (String.t() -> any())
```

---

## See Also

- [Main README.md](README.md) - Usage guide and examples
- [Airbnb Reservation Example](test/airbnb_reservation_component.ex) - Real-world usage
