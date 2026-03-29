# Parselet

A declarative text parsing library for Elixir that makes it easy to extract structured data from unstructured text using a simple, composable DSL.

## Features

- **Declarative DSL**: Define field extraction rules using a clean, readable syntax
- **Pattern Matching**: Use regex patterns to locate and capture data
- **Custom Extractors**: Define custom extraction logic using functions
- **Data Transformation**: Transform captured values with custom functions
- **Component-based**: Organize extraction logic into reusable components
- **Type-safe**: Works seamlessly with Elixir's pattern matching and type system

## Installation

Add Parselet to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:parselet, "~> 0.1"}
  ]
end
```

Then run `mix deps.get`.

## Quick Start

### 1. Define a Component

Create a module using `Parselet.Component` and define fields to extract:

```elixir
defmodule MyApp.Components.EmailParser do
  use Parselet.Component

  field :sender,
    pattern: ~r/From:\s*(.+)/,
    capture: :first,
    transform: &String.trim/1

  field :subject,
    pattern: ~r/Subject:\s*(.+)/,
    capture: :first

  field :date,
    pattern: ~r/Date:\s*(.+)/,
    capture: :first
end
```

### 2. Parse Text

Use `Parselet.parse/2` to extract data:

```elixir
email_text = """
From: alice@example.com
Subject: Meeting Tomorrow
Date: 2026-03-27
"""

result = Parselet.parse(email_text, components: [MyApp.Components.EmailParser])

# Result:
# %{
#   sender: "alice@example.com",
#   subject: "Meeting Tomorrow",
#   date: "2026-03-27"
# }
```

## API Reference

- [API Reference](API.md)
- [Developer Guide](DEVELOPER_GUIDE.md)

### `Parselet.Component`

The main module for defining extraction components.

#### `field(name, opts)`

Define a field to extract from text.

**Options:**
- `:pattern` - Regex pattern to match. Capture groups are extracted automatically.
- `:capture` - How to capture: `:first` (default, returns first capture group) or `:all` (returns all capture groups as a list)
- `:transform` - Optional function to transform the captured value. Default is identity function (`& &1`).
- `:function` - Custom extraction function. Takes the full text as input and returns the extracted value. Alternative to `:pattern`.
- `:required` - Boolean (default `false`). Mark field as required. Use with `Parselet.parse!/2` for validation.

If a separate component-level macro `preprocess` is defined, its function runs once
before field extraction. A component may also define `postprocess`, which runs
once after field extraction and may merge additional values into the parsed map.

Each component module also gets `parse/2` and `parse!/2` convenience helpers
that call `Parselet.parse(text, structs: [Component])`.

**Examples:**

```elixir
# Simple pattern matching
field :email,
  pattern: ~r/Email:\s*(\S+@\S+)/,
  capture: :first

# Capture multiple groups
field :date_range,
  pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,
  capture: :all

# Transform captured value
field :count,
  pattern: ~r/Count:\s*(\d+)/,
  capture: :first,
  transform: &String.to_integer/1

# Custom extraction function
field :listing_name,
  function: fn text ->
    text
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, ["Apartment", "House"]))
  end

# Preprocess text before extraction
preprocess fn text ->
  String.upcase(text)
end

field :name,
  pattern: ~r/NAME:\s*(.+)/,
  capture: :first

# Postprocess parsed values
postprocess fn fields ->
  if Map.has_key?(fields, :name) do
    %{name: String.downcase(fields.name), parsed_at: DateTime.utc_now()}
  else
    :ok
  end
end

# Mark as required
field :reservation_code,
  pattern: ~r/Code:\s+([A-Z0-9]+)/,
  capture: :first,
  required: true
```

### `Parselet.parse(text, components|structs: [...])`

Parse text using one or more components.

**Parameters:**
- `text` - String to parse
- `components` or `structs` - List of component modules to use for extraction

**Returns:** Map with extracted fields. Only fields that matched are included.

When required fields are missing or component postprocessing fails, `Parselet.parse/2` returns an error tuple:

```elixir
{:error, %{reason: "Missing required fields", fields: [:field_name]}}
```

**Examples:**

```elixir
result = Parselet.parse(text, components: [Component1, Component2])
# Fields from both components are merged into one map
```

```elixir
# Returns struct(s) when using `structs` option
result = Parselet.parse(text, structs: [MyApp.Components.EmailParser])
# => %MyApp.Components.EmailParser{sender: "alice@example.com", subject: "Meeting Tomorrow", date: "2026-03-27"}

# Multiple structs returned as a map when passing more than one module
result = Parselet.parse(text, structs: [Component1, Component2])
# => %{Component1 => %Component1{}, Component2 => %Component2{}}
```

### `Parselet.parse!(text, components|structs: [...])`

Parse text with validation of required fields.

**Parameters:**
- `text` - String to parse
- `components` or `structs` - List of component modules to use for extraction

**Returns:** Map with extracted fields (same as `parse/2`)

**Raises:** `ArgumentError` if any required fields are missing

**Example:**

```elixir
result = Parselet.parse!(text, components: [Component1])
# Raises ArgumentError if any fields marked as required: true are not found
```

## Real-World Example: Airbnb Reservation Parser

Here's a complete example parsing Airbnb reservation emails:

```elixir
defmodule MyApp.Components.AirbnbReservation do
  use Parselet.Component

  # Simple extraction with trimming
  field :reservation_code,
    pattern: ~r/Reservation code[:\s]+([A-Z0-9\-]+)/i,
    capture: :first

  # Extract and trim whitespace
  field :guest_name,
    pattern: ~r/Reservation for\s+([^\n]+)/i,
    capture: :first,
    transform: &String.trim/1

  # Multiple captures transformed into structured data
  field :date_range,
    pattern: ~r/([A-Za-z]{3} \d{1,2})\s*–\s*([A-Za-z]{3} \d{1,2})/,
    capture: :all,
    transform: &normalize_dates/1

  # Numeric extraction
  field :nights,
    pattern: ~r/(\d+)\s+nights?/i,
    capture: :first,
    transform: &String.to_integer/1

  # Currency extraction
  field :payout_amount,
    pattern: ~r/Payout[:\s]+\$?([\d,]+\.\d{2})/i,
    capture: :first,
    transform: fn amt ->
      amt
      |> String.replace(",", "")
      |> String.to_float()
    end

  # Complex custom extraction
  field :listing_name,
    function: fn text ->
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.find(fn line ->
        String.contains?(line, ["Apartment", "House"]) and
          not String.match?(line, ~r/^\d+\s+guests?/i)
      end)
    end

  defp normalize_dates([start_date, end_date]) do
    %{
      start: start_date,
      end: end_date
    }
  end
end

# Usage
email = File.read!("reservation.txt")
result = Parselet.parse(email, components: [MyApp.Components.AirbnbReservation])

# Result might be:
# %{
#   reservation_code: "ABC123XYZ",
#   guest_name: "Alice Johnson",
#   date_range: %{start: "Mar 28", end: "Apr 3"},
#   nights: 6,
#   payout_amount: 5452.22,
#   listing_name: "Beachfront Apartment"
# }
```

## Multi-Component Example: Invoice Processing

Parselet shines when you need to extract data from complex documents that contain multiple types of information. Here's an example of processing an invoice that contains both header information and line items:

```elixir
defmodule MyApp.Components.InvoiceHeader do
  use Parselet.Component

  field :invoice_number,
    pattern: ~r/Invoice\s*#?\s*([A-Z0-9\-]+)/i,
    capture: :first,
    required: true

  field :invoice_date,
    pattern: ~r/Date:\s*([^\n]+)/i,
    capture: :first,
    transform: &parse_date/1

  field :customer_name,
    pattern: ~r/Customer:\s*([^\n]+)/i,
    capture: :first,
    transform: &String.trim/1

  field :total_amount,
    pattern: ~r/Total:\s*\$?([\d,]+\.\d{2})/i,
    capture: :first,
    transform: fn amt ->
      amt
      |> String.replace(",", "")
      |> String.to_float()
    end,
    required: true

  defp parse_date(date_string) do
    # Simple date parsing - in real code you'd use a proper date library
    case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, date_string) do
      [_, year, month, day] ->
        Date.from_iso8601!("#{year}-#{month}-#{day}")
      _ ->
        date_string  # Return as string if parsing fails
    end
  end
end

defmodule MyApp.Components.InvoiceItems do
  use Parselet.Component

  field :line_items,
    function: fn text ->
      # Extract all line items from the invoice
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.match?(&1, ~r/^\d+\.\s+.+\s+\$\d/))
      |> Enum.map(&parse_line_item/1)
    end

  field :item_count,
    function: fn text ->
      # Count the number of line items
      text
      |> String.split("\n")
      |> Enum.count(&String.match?(&1, ~r/^\d+\.\s+.+\s+\$\d/))
    end

  field :subtotal,
    pattern: ~r/Subtotal:\s*\$?([\d,]+\.\d{2})/i,
    capture: :first,
    transform: fn amt ->
      amt
      |> String.replace(",", "")
      |> String.to_float()
    end

  field :tax_amount,
    pattern: ~r/Tax:\s*\$?([\d,]+\.\d{2})/i,
    capture: :first,
    transform: fn amt ->
      amt
      |> String.replace(",", "")
      |> String.to_float()
    end

  defp parse_line_item(line) do
    case Regex.run(~r/^(\d+)\.\s+(.+?)\s+\$([\d,]+\.\d{2})$/, line) do
      [_, quantity, description, price] ->
        %{
          quantity: String.to_integer(quantity),
          description: String.trim(description),
          unit_price: price |> String.replace(",", "") |> String.to_float()
        }
      _ ->
        nil
    end
  end
end

# Usage - parse with both components
invoice_text = """
INVOICE #INV-2026-001
Date: 2026-03-27
Customer: Acme Corporation

Line Items:
1. Office Chair    $299.99
2. Desk Lamp       $89.50
3. Keyboard        $129.99

Subtotal: $519.48
Tax: $41.56
Total: $561.04
"""

result = Parselet.parse(invoice_text, components: [
  MyApp.Components.InvoiceHeader,
  MyApp.Components.InvoiceItems
])

# Result combines fields from both components:
# %{
#   invoice_number: "INV-2026-001",
#   invoice_date: ~D[2026-03-27],
#   customer_name: "Acme Corporation",
#   total_amount: 561.04,
#   line_items: [
#     %{quantity: 1, description: "Office Chair", unit_price: 299.99},
#     %{quantity: 2, description: "Desk Lamp", unit_price: 89.50},
#     %{quantity: 3, description: "Keyboard", unit_price: 129.99}
#   ],
#   item_count: 3,
#   subtotal: 519.48,
#   tax_amount: 41.56
# }
```

This example demonstrates:

- **Component Separation**: Header info and line items are logically separated into different components
- **Complex Extraction**: Using custom functions for parsing structured line items
- **Data Transformation**: Converting strings to dates, numbers, and structured data
- **Field Combination**: All fields from both components are merged into a single result map
- **Required Fields**: Ensuring critical fields like invoice number and total are present

## Best Practices

### 1. Use Specific Patterns

Bad:
```elixir
field :amount, pattern: ~r/([\d.]+)/
```

Good:
```elixir
field :amount, pattern: ~r/Total:\s*\$([\d,]+\.\d{2})/i
```

### 2. Transform at Extraction

Don't extract strings when you need numbers:

Bad:
```elixir
field :count, pattern: ~r/Count: (\d+)/
# Returns: "42" (string)
```

Good:
```elixir
field :count,
  pattern: ~r/Count: (\d+)/,
  transform: &String.to_integer/1
# Returns: 42 (integer)
```

### 3. Use Custom Functions for Complex Logic

When regex patterns become too complex, use a custom function:

```elixir
field :main_content,
  function: fn text ->
    text
    |> String.split("\n")
    |> Enum.find(&is_main_content?/1)
  end
```

### 4. Handle Optional Fields

Fields that don't match simply won't appear in the result map:

```elixir
result = Parselet.parse(text, components: [MyComponent])

# Access with safe defaults
name = Map.get(result, :name, "Unknown")
```

### 5. Compose Multiple Components

Organize related fields into separate components:

```elixir
result = Parselet.parse(text, components: [
  MyApp.Components.Header,
  MyApp.Components.Body,
  MyApp.Components.Footer
])
```

## Common Patterns

### Email Extraction

```elixir
field :email,
  pattern: ~r/[\w\.-]+@[\w\.-]+\.\w+/,
  capture: :first
```

### Phone Number Extraction

```elixir
field :phone,
  pattern: ~r/(?:\+1[\s.-]?)?\(?(\d{3})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})/,
  capture: :all,
  transform: fn [area, exchange, line] ->
    "(#{area}) #{exchange}-#{line}"
  end
```

### Date Extraction

```elixir
field :date,
  pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,
  capture: :all,
  transform: fn [year, month, day] ->
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
```

### Currency Extraction

```elixir
field :price,
  pattern: ~r/\$?([\d,]+\.\d{2})/,
  capture: :first,
  transform: fn amount ->
    amount
    |> String.replace(",", "")
    |> String.to_float()
  end
```

### URL Extraction

```elixir
field :url,
  pattern: ~r/https?:\/\/[^\s]+/,
  capture: :first
```

## Testing

Example test for a component:

```elixir
defmodule MyApp.Components.EmailParserTest do
  use ExUnit.Case, async: true

  alias MyApp.Components.EmailParser

  test "parses email address" do
    text = "From: alice@example.com"
    result = Parselet.parse(text, components: [EmailParser])

    assert result.sender == "alice@example.com"
  end

  test "returns empty map when no fields match" do
    text = "Invalid content"
    result = Parselet.parse(text, components: [EmailParser])

    assert result == %{}
  end

  test "includes only matched fields" do
    text = "From: bob@example.com\nSubject: Test"
    result = Parselet.parse(text, components: [EmailParser])

    assert Map.has_key?(result, :sender)
    assert Map.has_key?(result, :subject)
    assert !Map.has_key?(result, :date)
  end
end
```

## Troubleshooting

### Field not being extracted?

1. **Check the regex pattern**
   ```elixir
   # Test your regex first
   Regex.run(~r/your_pattern/, text)
   ```

2. **Verify case sensitivity**
   ```elixir
   # Use /i flag for case-insensitive matching
   pattern: ~r/Pattern:/i
   ```

3. **Check capture groups**
   - `:first` captures only the first group
   - `:all` captures all groups
   ```elixir
   # This captures 2 groups
   pattern: ~r/(\d{4})-(\d{2})/
   capture: :all  # Returns ["2026", "03"]
   ```

### Transform function not working?

Ensure your transform function handles the input type correctly:

```elixir
# This will fail if input is a list
transform: &String.to_integer/1

# Use :all capture? Transform receives a list
field :date,
  pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,
  capture: :all,
  transform: fn [year, month, day] -> "#{year}-#{month}-#{day}" end
```

## Performance Considerations

- Patterns are compiled once at compile-time, so regex performance is optimal
- Multiple components are evaluated independently; you can parse with multiple components efficiently
- Transformation functions are called only for matched fields

## License

This project is released under MIT License.
