# Parselet Developer Guide

## Introduction

This guide is for developers who want to create custom components using the Parselet library. It covers component creation, best practices, and advanced techniques.

## Table of Contents

1. [Creating Your First Component](#creating-your-first-component)
2. [Field Definition Patterns](#field-definition-patterns)
3. [Component-Level Functions](#component-level-functions)
4. [Regex Patterns Guide](#regex-patterns-guide)
5. [Transform Functions](#transform-functions)
6. [Required Fields](#required-fields)
7. [Advanced Techniques](#advanced-techniques)
8. [Testing Components](#testing-components)
9. [Performance Optimization](#performance-optimization)
10. [Troubleshooting](#troubleshooting)

---

## Creating Your First Component

### Basic Component Structure

```elixir
defmodule MyApp.Parselet.Components.SimpleParser do
  use Parselet.Component

  # Define fields here
  field :name, pattern: ~r/Name:\s*(.+)/
end
```

### Step-by-Step Example

Let's create a component to parse invoice data:

```elixir
defmodule MyApp.Parselet.Components.InvoiceParser do
  use Parselet.Component

  # Invoice number - simple pattern
  field :invoice_number,
    pattern: ~r/Invoice #(\d+)/,
    capture: :first

  # Date with transformation
  field :date,
    pattern: ~r/Date: (\d{4})-(\d{2})-(\d{2})/,
    capture: :all,
    transform: fn [year, month, day] ->
      {:ok, date} = Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))
      date
    end

  # Amount with string cleaning
  field :total_amount,
    pattern: ~r/Total:\s*\$?([\d,]+\.\d{2})/,
    capture: :first,
    transform: fn amount ->
      amount
      |> String.replace(",", "")
      |> String.to_float()
    end

  # Custom extraction for complex logic
  field :vendor_name,
    function: fn text ->
      text
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, "Vendor:"))
      |> case do
        nil -> nil
        line -> String.replace(line, ~r/^Vendor:\s*/, "")
      end
    end
end
```

### Usage

```elixir
invoice_text = """
Invoice #12345
Date: 2026-03-27
Vendor: Acme Corp
Total: $1,234.56
"""

result = Parselet.parse(invoice_text, components: [MyApp.Parselet.Components.InvoiceParser])

# Result:
# %{
#   invoice_number: "12345",
#   date: ~D[2026-03-27],
#   vendor_name: "Acme Corp",
#   total_amount: 1234.56
# }
```

---

## Field Definition Patterns

### Pattern 1: Simple String Extraction

**Use when:** Capturing a simple text value

```elixir
field :email,
  pattern: ~r/Email:\s*(\S+@\S+)/,
  capture: :first
```

### Pattern 2: Numeric Extraction

**Use when:** Capturing numbers and converting to integers/floats

```elixir
field :age,
  pattern: ~r/Age:\s*(\d+)/,
  capture: :first,
  transform: &String.to_integer/1

field :salary,
  pattern: ~r/Salary:\s*\$?([\d,]+\.\d{2})/,
  capture: :first,
  transform: fn s -> s |> String.replace(",", "") |> String.to_float() end
```

### Pattern 3: Multiple Captures

**Use when:** Capturing multiple parts that belong together

```elixir
field :date,
  pattern: ~r/Date:\s*(\d{1,2})\/(\d{1,2})\/(\d{4})/,
  capture: :all,
  transform: fn [day, month, year] ->
    {:ok, date} = Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))
    date
  end

field :date_range,
  pattern: ~r/From\s+(\w+\s+\d+)\s+to\s+(\w+\s+\d+)/i,
  capture: :all,
  transform: fn [start_date, end_date] ->
    %{start: start_date, end: end_date}
  end
```

### Pattern 4: Line-based Extraction

**Use when:** Extracting a specific line or block of text

```elixir
field :subject,
  function: fn text ->
    text
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "Subject:"))
    |> case do
      nil -> nil
      line -> String.replace(line, ~r/^Subject:\s*/, "")
    end
  end
```

### Pattern 5: Conditional Extraction

**Use when:** Logic depends on content

```elixir
field :contact_method,
  function: fn text ->
    cond do
      String.match?(text, ~r/Email:\s*/) -> 
        Regex.run(~r/Email:\s*(\S+)/, text, capture: :all_but_first) |> List.first()
      String.match?(text, ~r/Phone:\s*/) -> 
        Regex.run(~r/Phone:\s*(.+)/, text, capture: :all_but_first) |> List.first()
      true -> 
        nil
    end
  end
```

### Pattern 6: Filtered List Extraction

**Use when:** Extracting and filtering multiple values

```elixir
field :tags,
  function: fn text ->
    text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "#"))
    |> Enum.map(&String.trim_leading(&1, "#"))
    |> Enum.map(&String.trim/1)
    |> case do
      [] -> nil
      tags -> tags
    end
  end
```

---

## Component-Level Functions

### Preprocess

Define a component-level preprocessing hook with `preprocess/1` to normalize the raw text before field extraction begins.

```elixir
preprocess fn text ->
  text
  |> String.replace("\r\n", "\n")
  |> String.trim()
end
```

You can also pass the function directly:

```elixir
preprocess &String.trim/1
```

The returned text is used for all downstream field extraction in that component.

### Postprocess

Define a component-level postprocessing hook with `postprocess/1` to run after all fields are parsed.

```elixir
postprocess fn result ->
  result
  |> Map.put(:parsed_at, DateTime.utc_now())
end
```

You can also pass the function directly:

```elixir
postprocess &add_metadata/1
```

The callback receives the parsed field map and must return either `:ok` or a map. When it returns a map, the map is merged into the parsed result.

---

## Regex Patterns Guide

### Email Pattern

```elixir
~r/[\w\.-]+@[\w\.-]+\.\w+/
# Examples: user@example.com, first.last@company.co.uk
```

### Phone Number

```elixir
# Simple: (123) 456-7890 or 123-456-7890
~r/\(?(\d{3})\)?[\s-]?(\d{3})[\s-]?(\d{4})/

# With country code
~r/(\+\d{1,3})?\s*\(?(\d{3})\)?[\s-]?(\d{3})[\s-]?(\d{4})/
```

### URL

```elixir
~r/https?:\/\/[^\s]+/

# Stricter version
~r/https?:\/\/(?:www\.)?[\w\.-]+\.\w+[^\s]*/
```

### Date Patterns

```elixir
# YYYY-MM-DD
~r/(\d{4})-(\d{2})-(\d{2})/

# MM/DD/YYYY
~r/(\d{1,2})\/(\d{1,2})\/(\d{4})/

# Mon DD, YYYY or January 1, 2026
~r/([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})/

# Natural format: 2026-03-27 or Mar 27
~r/(?:(\d{4})-)?(\d{1,2})-?(\d{1,2})|([A-Za-z]{3})\s+(\d{1,2})/
```

### Time Patterns

```elixir
# HH:MM or HH:MM:SS
~r/(\d{1,2}):(\d{2})(?::(\d{2}))?/

# With AM/PM
~r/(\d{1,2}):(\d{2})\s*([AP]M)/i
```

### Currency

```elixir
# $1,234.56 or USD 1234.56
~r/(?:\$|USD\s+)([\d,]+\.\d{2})/

# Multiple formats
~r/(?:\$|€|£|¥)([\d,]+\.\d{2})|(\d+)\s+(?:dollars|euros|pounds)/i
```

### IPv4 Address

```elixir
~r/(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/
```

### Hashtags

```elixir
~r/#[\w]+/
```

### Mentions (@username)

```elixir
~r/@[\w]+/
```

### Price Range

```elixir
~r/\$(\d+(?:,\d{3})*)\s*(?:to|[-–]|through)\s*\$(\d+(?:,\d{3})*)/
```

---

## Transform Functions

### Common Transform Patterns

#### String Operations

```elixir
# Trim whitespace
transform: &String.trim/1

# Uppercase
transform: &String.upcase/1

# Remove common prefixes
transform: fn s -> String.replace(s, ~r/^(The|A|An)\s+/i, "") end

# Join with separator
transform: fn list -> Enum.join(list, ", ") end
```

#### Type Conversions

```elixir
# String to integer
transform: &String.to_integer/1

# String to float
transform: &String.to_float/1

# String to atom (use cautiously!)
transform: &String.to_atom/1

# String to list of atoms
transform: fn s -> s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.map(&String.to_atom/1) end
```

#### Date/Time Handling

```elixir
# Parse ISO date
transform: &Date.from_iso8601!/1

# Format date
transform: fn date_str ->
  {:ok, date} = Date.from_iso8601(date_str)
  Calendar.strftime(date, "%B %d, %Y")
end

# Parse time
transform: fn time_str ->
  case Time.from_iso8601(time_str) do
    {:ok, time, _} -> time
    {:error, _} -> nil
  end
end
```

#### Cleaning and Normalization

```elixir
# Remove currency symbols
transform: fn s -> String.replace(s, ~r/[$€£¥]/, "") end

# Remove commas from numbers
transform: fn s -> String.replace(s, ",", "") end

# Normalize whitespace (multiple spaces to single)
transform: fn s -> String.trim(s) |> String.replace(~r/\s+/, " ") end

# URL decode
transform: &URI.decode/1

# HTML unescape
transform: fn s ->
  s
  |> String.replace("&amp;", "&")
  |> String.replace("&lt;", "<")
  |> String.replace("&gt;", ">")
  |> String.replace("&quot;", "\"")
end
```

#### Conditional Transforms

```elixir
# Transform only if matches condition
transform: fn value ->
  if String.contains?(value, "@") do
    {:ok, value}  # Email-like
  else
    {:error, "invalid"}
  end
end

# Multi-way transform
transform: fn value ->
  cond do
    String.contains?(value, "$") -> String.to_float(String.replace(value, "$", ""))
    String.contains?(value, "%") -> String.to_float(String.replace(value, "%", ""))
    true -> value
  end
end
```

#### Complex Transformations

```elixir
# Build map from multiple captures
transform: fn [name, email, phone] ->
  %{
    name: String.trim(name),
    email: String.trim(email),
    phone: String.trim(phone)
  }
end

# Parse structured data
transform: fn csv_line ->
  csv_line
  |> String.split(",")
  |> Enum.map(&String.trim/1)
  |> Enum.with_index()
  |> Enum.into(%{}, fn {value, idx} -> {String.to_atom("field_#{idx}"), value} end)
end

# Chain multiple operations
transform: fn value ->
  value
  |> String.trim()
  |> String.downcase()
  |> String.replace(" ", "_")
  |> String.to_atom()
end
```

---

## Required Fields

Mark fields as required to ensure critical data is always present in parsed results.

### Basic Usage

```elixir
defmodule MyApp.Parselet.Components.PaymentParser do
  use Parselet.Component

  # Required fields
  field :transaction_id,
    pattern: ~r/TXN:\s*([A-Z0-9]+)/,
    required: true

  field :amount,
    pattern: ~r/Amount:\s*\$?([\d,]+\.\d{2})/,
    capture: :first,
    transform: fn s -> s |> String.replace(",", "") |> String.to_float() end,
    required: true

  # Optional fields
  field :description,
    pattern: ~r/Description:\s*(.+)/

  field :reference,
    pattern: ~r/Ref:\s*(.+)/
end
```

### Usage with Validation

```elixir
# Non-strict parsing: returns whatever fields it finds
result = Parselet.parse(text, components: [PaymentParser])
# => %{transaction_id: "TXN123", amount: 99.99, ...}
# or
# => %{description: "Order #456"} (if required fields are missing)

# Strict parsing: raises if required fields missing
result = Parselet.parse!(text, components: [PaymentParser])
# => %{transaction_id: "TXN123", amount: 99.99, ...}
# or
# => raises ArgumentError if transaction_id or amount missing
```

### Difference Between parse/2 and parse!/2

- **`Parselet.parse/2`** - Lenient, returns whatever fields match
- **`Parselet.parse!/2`** - Strict, raises `ArgumentError` if any required fields missing

```elixir
# If payment data has no amount:
incomplete_text = "TXN: ABC123"

# Non-strict: succeeds, returns what matched
result = Parselet.parse(incomplete_text, components: [PaymentParser])
# => %{transaction_id: "ABC123"}

# Strict: fails
Parselet.parse!(incomplete_text, components: [PaymentParser])
# => raises: ArgumentError, "Missing required fields: [:amount]"
```

### Manual Validation

For custom validation logic, use `Parselet.Field.validate_required/2`:

```elixir
fields_map = PaymentParser.__parselet_fields__()
result = Parselet.parse(text, components: [PaymentParser])

missing = Parselet.Field.validate_required(result, fields_map)

case missing do
  [] ->
    {:ok, result}

  _ ->
    {:error, "Missing required: #{inspect(missing)}"}
end
```

### Best Practices

1. **Mark critical fields as required**
   ```elixir
   # ID, transaction codes, amounts
   field :order_id, pattern: ~r/Order:\s*(\d+)/, required: true
   ```

2. **Optional fields stay optional**
   ```elixir
   # Notes, comments, descriptions
   field :notes, function: fn text -> extract_notes(text) end
   # required: false is default
   ```

3. **Use parse!/2 at entry points**
   ```elixir
   def process_payment(text) do
     # Strict validation at API boundary
     Parselet.parse!(text, components: [PaymentParser])
   end
   ```

4. **Use parse/2 for incremental data**
   ```elixir
   def update_user(text) do
     # Lenient parsing allows partial updates
     partial = Parselet.parse(text, components: [UserParser])
     update_user_fields(user, partial)
   end
   ```

---

## Advanced Techniques

### Chained Components

Use multiple components for different aspects of the data:

```elixir
defmodule MyApp.Parselet.Components.Header do
  use Parselet.Component
  
  field :title, pattern: ~r/Title:\s*(.+)/
  field :date, pattern: ~r/Date:\s*(.+)/
end

defmodule MyApp.Parselet.Components.Body do
  use Parselet.Component
  
  field :content, function: fn text ->
    String.split(text, "\n")
    |> Enum.find(&String.contains?(&1, "Content:"))
  end
end

# Usage
result = Parselet.parse(text, components: [
  MyApp.Parselet.Components.Header,
  MyApp.Parselet.Components.Body
])
# => Fields from both components merged
```

### Stateful Component Organization

Create domain-specific component modules:

```elixir
defmodule MyApp.Parselet.Parsers do
  def invoice, do: MyApp.Parselet.Components.InvoiceParser
  def email, do: MyApp.Parselet.Components.EmailParser
  def receipt, do: MyApp.Parselet.Components.ReceiptParser
end

# Usage
result = Parselet.parse(text, components: [MyApp.Parselet.Parsers.invoice()])
```

### Composable Field Definitions

Create reusable field helpers:

```elixir
defmodule MyApp.Parselet.FieldHelpers do
  def email_field(name, opts \\ []) do
    Keyword.merge([
      pattern: ~r/Email:\s*(\S+@\S+)/,
      capture: :first
    ], opts)
  end

  def date_field(name, opts \\ []) do
    Keyword.merge([
      pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,
      capture: :all,
      transform: fn [y, m, d] ->
        {:ok, d} = Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d))
        d
      end
    ], opts)
  end
end

# Usage
defmodule MyApp.Parselet.Components.UserParser do
  use Parselet.Component
  import MyApp.Parselet.FieldHelpers

  field :email, email_field(:email)
  field :birth_date, date_field(:birth_date)
end
```

### Fallback Extraction

Try multiple patterns in order:

```elixir
field :phone,
  function: fn text ->
    patterns = [
      ~r/Phone:\s*(.+)/,
      ~r/Tel:\s*(.+)/,
      ~r/Contact:\s*(.+)/,
      ~r/\(?\d{3}\)?[\s-]?\d{3}[\s-]?\d{4}/
    ]
    
    Enum.find_value(patterns, fn pattern ->
      Regex.run(pattern, text, capture: :all_but_first) |> List.first()
    end)
  end
```

---

## Testing Components

### Unit Tests

```elixir
defmodule MyApp.Parselet.Components.InvoiceParserTest do
  use ExUnit.Case, async: true

  alias MyApp.Parselet.Components.InvoiceParser

  describe "invoice parsing" do
    test "extracts invoice number" do
      text = "Invoice #12345"
      result = Parselet.parse(text, components: [InvoiceParser])
      
      assert result.invoice_number == "12345"
    end

    test "extracts and converts date" do
      text = "Date: 2026-03-27"
      result = Parselet.parse(text, components: [InvoiceParser])
      
      assert result.date == ~D[2026-03-27]
    end

    test "handles missing optional fields" do
      text = "Invoice #999"
      result = Parselet.parse(text, components: [InvoiceParser])
      
      assert Map.has_key?(result, :invoice_number)
      refute Map.has_key?(result, :date)
    end
  end
end
```

### Property-Based Tests with Generators

```elixir
defmodule MyApp.Parselet.Components.EmailParserTest do
  use ExUnit.Case
  use ExUnitProperties

  alias MyApp.Parselet.Components.EmailParser

  property "extracts valid email addresses" do
    check all email <- email_gen() do
      text = "Contact: #{email}"
      result = Parselet.parse(text, components: [EmailParser])
      
      assert Map.has_key?(result, :email)
      assert result.email == email
    end
  end

  defp email_gen do
    gen_all(
      user <- string(:printable, min_length: 1),
      domain <- string(:alphanumeric, min_length: 1),
      extension <- string(:alphanumeric, min_length: 2)
    ) do
      "#{user}@#{domain}.#{extension}"
    end
  end
end
```

### Integration Tests

```elixir
defmodule MyApp.Parselet.InvoiceParserIntegrationTest do
  use ExUnit.Case

  test "parses complete real-world invoice" do
    invoice_text = File.read!("test/fixtures/invoice.txt")
    
    result = Parselet.parse(invoice_text, components: [
      MyApp.Parselet.Components.InvoiceParser
    ])
    
    assert result.invoice_number == "INV-2026-001"
    assert result.date == ~D[2026-03-27]
    assert result.total_amount == 1234.56
    assert result.vendor_name == "Acme Corp"
  end
end
```

---

## Performance Optimization

### Regex Compilation

Regex patterns are compiled at compile-time, so use them liberally:

```elixir
# ✅ Good: Compiled once
field :email, pattern: ~r/\S+@\S+/

# ❌ Avoid: Recompiled at runtime
field :email, pattern: Regex.compile!("\\S+@\\S+")
```

### Component Organization

Group related fields to reduce parsing passes:

```elixir
# ✅ Good: Single parse call
result = Parselet.parse(text, components: [AllParser])

# ❌ Suboptimal: Multiple parse calls
result1 = Parselet.parse(text, components: [Parser1])
result2 = Parselet.parse(text, components: [Parser2])
result = Map.merge(result1, result2)
```

### Early Termination for Optional Fields

Use functions for expensive operations on optional fields:

```elixir
# ✅ Good: Only processes if needed
field :complex_data,
  function: fn text ->
    if String.contains?(text, "COMPLEX") do
      # Expensive operation
      parse_complex_data(text)
    else
      nil
    end
  end
```

### Large Text Handling

Pre-filter before extraction:

```elixir
# ✅ Good: Extract relevant section first
field :section_data,
  function: fn text ->
    case String.split(text, "---SECTION---") do
      [_, section, _] -> parse_section(section)
      _ -> nil
    end
  end
```

---

## Troubleshooting

### Field Not Extracting

**Problem:** Pattern defined but field not in result

**Debugging steps:**

```elixir
# 1. Test regex directly
text = "Invoice #12345"
Regex.run(~r/Invoice #(\d+)/, text, capture: :all_but_first)
# Should return ["12345"]

# 2. Check field definition
field :invoice_number,
  pattern: ~r/Invoice #(\d+)/,
  capture: :first
# Ensure you have exactly one capture group for :first

# 3. Verify component is included
result = Parselet.parse(text, components: [MyComponent])
IO.inspect(result)
```

### Transform Function Errors

**Problem:** Transform crashes on matched text

```elixir
# ❌ Bad: Assumes specific format
field :count,
  pattern: ~r/Count: (\w+)/,
  capture: :first,
  transform: &String.to_integer/1
# Fails if pattern matches "abc"

# ✅ Good: Handle edge cases
field :count,
  pattern: ~r/Count: (\d+)/,  # Only match digits
  capture: :first,
  transform: &String.to_integer/1
```

### Multiple Captures Not Working

**Problem:** `:all` capture not returning list

```elixir
# ❌ Wrong: :all requires multiple groups
field :date,
  pattern: ~r/(\d{4}-\d{2}-\d{2})/,  # Single group
  capture: :all
# Returns ["2026-03-27"] not grouped values

# ✅ Correct: Multiple groups
field :date,
  pattern: ~r/(\d{4})-(\d{2})-(\d{2})/,  # Three groups
  capture: :all
# Returns ["2026", "03", "27"]
```

### Case Sensitivity Issues

**Problem:** Pattern not matching due to case

```elixir
# ❌ Fragile: Case-sensitive
field :amount,
  pattern: ~r/Total: \$(.+)/

# ✅ Robust: Case-insensitive
field :amount,
  pattern: ~r/Total: \$(.+)/i
```

### Whitespace Handling

**Problem:** Captured value has unwanted whitespace

```elixir
# ❌ Doesn't trim
field :name,
  pattern: ~r/Name: (.+)/,
  capture: :first

# ✅ Trims whitespace
field :name,
  pattern: ~r/Name: (.+)/,
  capture: :first,
  transform: &String.trim/1
```

---

## Best Practices Checklist

- [ ] Keep patterns specific and precise
- [ ] Always include transforms for type conversions
- [ ] Test patterns in isolation with IEx first
- [ ] Use case-insensitive flag (/i) when appropriate
- [ ] Trim whitespace in transforms
- [ ] Handle edge cases in extraction functions
- [ ] Document component purpose with module attributes
- [ ] Group related fields in components
- [ ] Use meaningful field names
- [ ] Write comprehensive tests
- [ ] Profile performance with large datasets
- [ ] Keep extraction logic simple and focused

---

## See Also

- [API Documentation](API.md)
- [Main README](README.md)
