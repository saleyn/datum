defmodule Parselet.ComponentTest do
  use ExUnit.Case, async: true

  describe "basic field definition" do
    defmodule BasicComponent do
      use Parselet.Component

      field :name, pattern: ~r/Name:\s*(.+)/
      field :age, pattern: ~r/Age:\s*(\d+)/, capture: :first, transform: &String.to_integer/1
    end

    test "extracts fields using patterns" do
      text = "Name: Alice\nAge: 30"
      result = Parselet.parse(text, components: [BasicComponent])

      assert result.name == "Alice"
      assert result.age == 30
    end

    test "returns empty map when no fields match" do
      text = "No data here"
      result = Parselet.parse(text, components: [BasicComponent])

      assert result == %{}
    end

    test "includes only matched fields" do
      text = "Name: Bob"
      result = Parselet.parse(text, components: [BasicComponent])

      assert Map.has_key?(result, :name)
      refute Map.has_key?(result, :age)
    end

    test "accesses __parselet_fields__ function" do
      fields = BasicComponent.__parselet_fields__()

      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :age)
      assert is_struct(fields.name, Parselet.Field)
      assert is_struct(fields.age, Parselet.Field)
    end
  end

  describe "pattern variations" do
    defmodule PatternComponent do
      use Parselet.Component

      field :email, pattern: ~r/Email:\s*(\S+@\S+)/

      field :code, pattern: ~r/CODE:\s*([A-Z0-9]+)/i

      field :value, pattern: ~r/(?:Value|Amount):\s*(.+)/
    end

    test "captures with first modifier" do
      text = "Email: user@example.com"
      result = Parselet.parse(text, components: [PatternComponent])

      assert result.email == "user@example.com"
    end

    test "case insensitive matching" do
      text1 = "code: ABC123"
      text2 = "CODE: ABC123"
      text3 = "Code: ABC123"

      result1 = Parselet.parse(text1, components: [PatternComponent])
      result2 = Parselet.parse(text2, components: [PatternComponent])
      result3 = Parselet.parse(text3, components: [PatternComponent])

      assert result1.code == "ABC123"
      assert result2.code == "ABC123"
      assert result3.code == "ABC123"
    end

    test "alternation in patterns" do
      text1 = "Value: 100"
      text2 = "Amount: 200"

      result1 = Parselet.parse(text1, components: [PatternComponent])
      result2 = Parselet.parse(text2, components: [PatternComponent])

      assert result1.value == "100"
      assert result2.value == "200"
    end
  end

  describe "transform functions" do
    defmodule TransformComponent do
      use Parselet.Component

      field :trimmed,
        pattern: ~r/Name:\s*(.+)/,
        transform: &String.trim/1

      field :uppercase,
        pattern: ~r/City:\s*(.+)/,
        transform: &String.upcase/1

      field :number,
        pattern: ~r/Count:\s*(\d+)/,
        transform: &String.to_integer/1

      field :amount,
        pattern: ~r/Price:\s*\$?([\d,]+\.\d+)/,
        transform: fn s -> s |> String.replace(",", "") |> String.to_float() end
    end

    test "string trim transformation" do
      text = "Name:    Alice    "
      result = Parselet.parse(text, components: [TransformComponent])

      assert result.trimmed == "Alice"
    end

    test "uppercase transformation" do
      text = "City: new york"
      result = Parselet.parse(text, components: [TransformComponent])

      assert result.uppercase == "NEW YORK"
    end

    test "integer conversion" do
      text = "Count: 42"
      result = Parselet.parse(text, components: [TransformComponent])

      assert result.number == 42
      assert is_integer(result.number)
    end

    test "currency formatting" do
      text = "Price: $1,234.56"
      result = Parselet.parse(text, components: [TransformComponent])

      assert result.amount == 1234.56
      assert is_float(result.amount)
    end
  end

  describe "custom function extractors" do
    defmodule FunctionComponent do
      use Parselet.Component

      field :first_line,
        function: fn text ->
          text |> String.split("\n") |> List.first()
        end

      field :line_count,
        function: fn text ->
          text |> String.split("\n") |> length()
        end

      field :summary,
        function: fn text ->
          case String.split(text, "---") do
            [_header, summary, _footer] -> String.trim(summary)
            _ -> nil
          end
        end

      field :has_error,
        function: fn text ->
          String.contains?(text, "ERROR")
        end
    end

    test "extracts first line" do
      text = "Line 1\nLine 2\nLine 3"
      result = Parselet.parse(text, components: [FunctionComponent])

      assert result.first_line == "Line 1"
    end

    test "counts lines" do
      text = "Line 1\nLine 2\nLine 3"
      result = Parselet.parse(text, components: [FunctionComponent])

      assert result.line_count == 3
    end

    test "extracts section between delimiters" do
      text = "Header\n---\nMain content\n---\nFooter"
      result = Parselet.parse(text, components: [FunctionComponent])

      assert result.summary == "Main content"
    end

    test "returns nil when delimiter not found" do
      text = "Single line"
      result = Parselet.parse(text, components: [FunctionComponent])

      assert Map.has_key?(result, :summary) == false
    end

    test "boolean extraction" do
      text1 = "Status: ERROR in processing"
      text2 = "Status: OK"

      result1 = Parselet.parse(text1, components: [FunctionComponent])
      result2 = Parselet.parse(text2, components: [FunctionComponent])

      assert result1.has_error == true
      assert result2.has_error == false
    end
  end

  describe "required fields" do
    defmodule StrictComponent do
      use Parselet.Component

      field :id, pattern: ~r/ID:\s*(\d+)/, required: true
      field :name, pattern: ~r/Name:\s*(.+)/, required: true
      field :email, pattern: ~r/Email:\s*(.+)/
    end

    test "parse with all required fields present" do
      text = "ID: 123\nName: Alice\nEmail: alice@example.com"
      result = Parselet.parse(text, components: [StrictComponent])

      assert result.id == "123"
      assert result.name == "Alice"
      assert result.email == "alice@example.com"
    end

    test "parse with missing required field" do
      text = "ID: 123\nEmail: bob@example.com"
      result = Parselet.parse(text, components: [StrictComponent])

      assert result.id == "123"
      assert result.email == "bob@example.com"
      assert !Map.has_key?(result, :name)
    end

    test "parse! with all required fields present" do
      text = "ID: 456\nName: Charlie"
      result = Parselet.parse!(text, components: [StrictComponent])

      assert result.id == "456"
      assert result.name == "Charlie"
    end

    test "parse! raises when required field missing" do
      text = "ID: 789"

      assert_raise ArgumentError, "Missing required fields: [:name]", fn ->
        Parselet.parse!(text, components: [StrictComponent])
      end
    end

    test "parse! raises with multiple missing required fields" do
      text = "Email: test@example.com"

      assert_raise ArgumentError, fn ->
        Parselet.parse!(text, components: [StrictComponent])
      end
    end

    test "required false is default" do
      defmodule OptionalComponent do
        use Parselet.Component

        field :optional_field, pattern: ~r/Data:\s*(.+)/
      end

      text = "No data"
      result = Parselet.parse(text, components: [OptionalComponent])

      assert result == %{}
    end
  end

  describe "multiple components" do
    defmodule Component1 do
      use Parselet.Component

      field :name, pattern: ~r/Name:\s*(.+)/
      field :age, pattern: ~r/Age:\s*(\d+)/, transform: &String.to_integer/1
    end

    defmodule Component2 do
      use Parselet.Component

      field :email, pattern: ~r/Email:\s*(.+)/
      field :phone, pattern: ~r/Phone:\s*(.+)/
    end

    test "merges results from multiple components" do
      text = "Name: Alice\nAge: 30\nEmail: alice@example.com\nPhone: 555-1234"
      result = Parselet.parse(text, components: [Component1, Component2])

      assert result.name == "Alice"
      assert result.age == 30
      assert result.email == "alice@example.com"
      assert result.phone == "555-1234"
    end

    test "handles overlapping field names" do
      defmodule ComponentA do
        use Parselet.Component

        field :id, pattern: ~r/ID:\s*(\d+)/
      end

      defmodule ComponentB do
        use Parselet.Component

        field :id, pattern: ~r/Code:\s*([A-Z]+)/
      end

      text = "ID: 123\nCode: ABC"
      result = Parselet.parse(text, components: [ComponentA, ComponentB])

      assert result.id == "ABC"
    end

    test "parse! checks all components required fields" do
      defmodule StrictA do
        use Parselet.Component

        field :required_a, pattern: ~r/A:\s*(.+)/, required: true
      end

      defmodule StrictB do
        use Parselet.Component

        field :required_b, pattern: ~r/B:\s*(.+)/, required: true
      end

      text = "A: Present"

      assert_raise ArgumentError, "Missing required fields: [:required_b]", fn ->
        Parselet.parse!(text, components: [StrictA, StrictB])
      end
    end
  end

  describe "edge cases" do
    defmodule EdgeComponent do
      use Parselet.Component

      field :empty, pattern: ~r/Empty:\s*(.*)/
      field :multiline, function: fn text -> String.split(text, "\n") end
    end

    test "handles empty captures" do
      text = "Empty: "
      result = Parselet.parse(text, components: [EdgeComponent])

      assert result.empty == ""
    end

    test "handles multiline text in functions" do
      text = "Line 1\nLine 2\nLine 3"
      result = Parselet.parse(text, components: [EdgeComponent])

      assert result.multiline == ["Line 1", "Line 2", "Line 3"]
    end

    test "handles special characters in patterns" do
      defmodule SpecialComponent do
        use Parselet.Component

        field :path, pattern: ~r/Path:\s*(.+)/
        field :url, pattern: ~r/URL:\s*(.+)/
      end

      text = "Path: /home/user/file.txt\nURL: https://example.com?id=123&name=test"
      result = Parselet.parse(text, components: [SpecialComponent])

      assert result.path == "/home/user/file.txt"
      assert result.url == "https://example.com?id=123&name=test"
    end
  end

  describe "field struct properties" do
    test "field struct contains all properties" do
      defmodule TestComponent do
        use Parselet.Component

        field :test, pattern: ~r/Test:\s*(.+)/, required: true
      end

      fields = TestComponent.__parselet_fields__()
      field = fields.test

      assert field.name == :test
      assert field.pattern == ~r/Test:\s*(.+)/
      assert field.capture == :first
      assert field.required == true
      assert is_function(field.transform)
    end

    test "field with all options" do
      defmodule FullComponent do
        use Parselet.Component

        field :complex,
          pattern: ~r/(\d+)-(\d+)/,
          capture: :all,
          transform: fn [a, b] -> String.to_integer(a) + String.to_integer(b) end,
          required: false
      end

      fields = FullComponent.__parselet_fields__()
      field = fields.complex

      assert field.capture == :all
      assert field.required == false
    end

    test "field with function instead of pattern" do
      defmodule FunctionOnlyComponent do
        use Parselet.Component

        field :computed, function: fn _text -> 42 end
      end

      fields = FunctionOnlyComponent.__parselet_fields__()
      field = fields.computed

      assert field.function != nil
      assert field.pattern == nil
    end
  end

  describe "extraction priority" do
    defmodule PriorityComponent do
      use Parselet.Component

      field :priority,
        pattern: ~r/Pattern:\s*(.+)/,
        function: fn _text -> "function_result" end
    end

    test "function extraction takes priority over pattern" do
      text = "Pattern: from_pattern"
      result = Parselet.parse(text, components: [PriorityComponent])

      assert result.priority == "function_result"
    end
  end

  describe "real world scenarios" do
    defmodule InvoiceComponent do
      use Parselet.Component

      field :invoice_id, pattern: ~r/Invoice #(\d+)/, required: true

      field :amount,
        pattern: ~r/Total:\s*\$?([\d,]+\.\d+)/,
        transform: fn s -> s |> String.replace(",", "") |> String.to_float() end,
        required: true

      field :vendor, pattern: ~r/Vendor:\s*(.+)/
    end

    test "parses valid invoice" do
      invoice = """
      Invoice #12345
      Vendor: ACME Corp
      Total: $1,234.56
      """

      result = Parselet.parse!(invoice, components: [InvoiceComponent])

      assert result.invoice_id == "12345"
      assert result.amount == 1234.56
      assert result.vendor == "ACME Corp"
    end

    test "rejects invoice with missing required fields" do
      incomplete = """
      Invoice #999
      Vendor: ACME Corp
      """

      assert_raise ArgumentError, fn ->
        Parselet.parse!(incomplete, components: [InvoiceComponent])
      end
    end

    test "handles invoice with optional fields missing" do
      minimal = """
      Invoice #999
      Total: $500.00
      """

      result = Parselet.parse!(minimal, components: [InvoiceComponent])

      assert result.invoice_id == "999"
      assert result.amount == 500.0
      assert !Map.has_key?(result, :vendor)
    end
  end

  describe "airbnb reservation component" do
    defmodule AirbnbReservationComponent do
      use Parselet.Component

      field :reservation_code, pattern: ~r/Reservation code:\s*([A-Z0-9]+)/
      field :guest_name, pattern: ~r/(?:You're hosting|Reservation for)\s+(.+)/
      field :check_in_date, pattern: ~r/(\w{3} \d{1,2}) – \w{3} \d{1,2}/, capture: :first
      field :check_out_date, pattern: ~r/\w{3} \d{1,2} – (\w{3} \d{1,2})/, capture: :first
      field :nights, pattern: ~r/· (\d+) nights/, capture: :first, transform: &String.to_integer/1
      field :property_name,
        function: fn text ->
          lines =
            text
            |> String.split("\n", trim: true)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          date_line = ~r/[A-Za-z]{3}\s+\d{1,2}\s+[–—-]\s+[A-Za-z]{3}\s+\d{1,2}.*\b\d+\s+nights?/i

          lines
          |> case do
            [] -> nil

            ls ->
              case Enum.find_index(ls, &String.match?(&1, date_line)) do
                nil ->
                  ls
                  |> Enum.find(fn line ->
                    String.contains?(line, ["BR", "Apartment", "House", "Gateway"]) and
                      not String.match?(line, ~r/^(Reservation|Reservation code|Check-?in|Checkout|Your earnings|Payout|\d+\s+guests?)/i)
                  end)

                idx ->
                  ls
                  |> Enum.drop(idx + 1)
                  |> Enum.find(fn line ->
                    line not in [""] and
                      not String.match?(line, ~r/^(\d+\s+guests?|Check-?in|Checkout|Your earnings|Payout)/i)
                  end)
              end
          end
        end
      field :guest_count, pattern: ~r/(\d+) guests/, capture: :first, transform: &String.to_integer/1
      field :check_in_time, pattern: ~r/Check-in:\s*(.+)/
      field :check_out_time, pattern: ~r/Checkout:\s*(.+)/
      field :earnings, pattern: ~r/(?:Your earnings|Payout):\s*\$([\d,]+\.\d{2})/, capture: :first, transform: fn(amount) ->
        amount |> String.replace(",", "") |> String.to_float()
      end
    end

    test "parses airbnb reservation 1 fixture" do
      fixture_path = Path.join([__DIR__, "support", "fixtures", "airbnb_reservation_1.txt"])
      text = File.read!(fixture_path)

      result = Parselet.parse(text, components: [AirbnbReservationComponent])

      assert result.reservation_code == "ABC123XYZ"
      assert result.guest_name == "Kari"
      assert result.check_in_date == "Mar 28"
      assert result.check_out_date == "Apr 3"
      assert result.nights == 6
      assert result.property_name == "Couver A 2BR · Spacious 2/1 Unit Prime Location"
      assert result.guest_count == 3
      assert result.check_in_time == "4:00 PM"
      assert result.check_out_time == "10:00 AM"
      assert result.earnings == 5452.22
    end

    test "parses airbnb reservation 2 fixture" do
      fixture_path = Path.join([__DIR__, "support", "fixtures", "airbnb_reservation_2.txt"])
      text = File.read!(fixture_path)

      result = Parselet.parse(text, components: [AirbnbReservationComponent])

      assert result.reservation_code == "HMH3HYYX2J"
      assert result.guest_name == "Steven James"
      assert result.check_in_date == "Feb 12"
      assert result.check_out_date == "Feb 28"
      assert result.nights == 16
      assert result.property_name == "Your Dream Dual-Zone Gateway With Private Pool"
      assert result.guest_count == 6
      assert result.check_in_time == "4:00 PM"
      assert result.check_out_time == "10:00 AM"
      assert result.earnings == 5603.00
    end
  end

  describe "multi-components parsing" do
    defmodule PersonalInfoComponent do
      use Parselet.Component

      field :name, pattern: ~r/Name:\s*(.+)/
      field :age, pattern: ~r/Age:\s*(\d+)/, transform: &String.to_integer/1
      field :email, pattern: ~r/Email:\s*(\S+@\S+)/
    end

    defmodule AddressComponent do
      use Parselet.Component

      field :street, pattern: ~r/Street:\s*(.+)/
      field :city, pattern: ~r/City:\s*(.+)/
      field :zip_code, pattern: ~r/ZIP:\s*(\d{5})/
    end

    defmodule EmploymentComponent do
      use Parselet.Component

      field :company, pattern: ~r/Company:\s*(.+)/
      field :position, pattern: ~r/Position:\s*(.+)/
      field :salary, pattern: ~r/Salary:\s*\$([\d,]+(?:\.\d{2})?)/, transform: fn(amount) ->
        amount |> String.replace(",", "") |> String.to_float()
      end
    end

    test "parses text using multiple components" do
      text = """
      Name: John Doe
      Age: 35
      Email: john.doe@example.com

      Street: 123 Main St
      City: Anytown
      ZIP: 12345

      Company: Tech Corp
      Position: Senior Developer
      Salary: $85,000.00
      """

      result = Parselet.parse(text, components: [PersonalInfoComponent, AddressComponent, EmploymentComponent])

      # Personal info fields
      assert result.name == "John Doe"
      assert result.age == 35
      assert result.email == "john.doe@example.com"

      # Address fields
      assert result.street == "123 Main St"
      assert result.city == "Anytown"
      assert result.zip_code == "12345"

      # Employment fields
      assert result.company == "Tech Corp"
      assert result.position == "Senior Developer"
      assert result.salary == 85000.0
    end

    test "handles overlapping field names across components" do
      defmodule OverlapComponentA do
        use Parselet.Component
        field :value, pattern: ~r/Value A:\s*(.+)/
      end

      defmodule OverlapComponentB do
        use Parselet.Component
        field :value, pattern: ~r/Value B:\s*(.+)/
      end

      text = "Value A: First\nValue B: Second"
      result = Parselet.parse(text, components: [OverlapComponentA, OverlapComponentB])

      # Last component wins for overlapping field names
      assert result.value == "Second"
    end

    test "combines fields from multiple components with required validation" do
      defmodule MultiRequiredComponent do
        use Parselet.Component
        field :required_field, pattern: ~r/Required:\s*(.+)/, required: true
      end

      defmodule MultiOptionalComponent do
        use Parselet.Component
        field :optional_field, pattern: ~r/Optional:\s*(.+)/
      end

      text = "Required: Important Data\nOptional: Extra Info"
      result = Parselet.parse!(text, components: [MultiRequiredComponent, MultiOptionalComponent])

      assert result.required_field == "Important Data"
      assert result.optional_field == "Extra Info"
    end

    test "fails when required field in any component is missing" do
      defmodule MultiStrictComponent do
        use Parselet.Component
        field :must_have, pattern: ~r/Must Have:\s*(.+)/, required: true
      end

      defmodule MultiLenientComponent do
        use Parselet.Component
        field :nice_to_have, pattern: ~r/Nice To Have:\s*(.+)/
      end

      text = "Nice To Have: Bonus Data"
      # This should raise because MultiStrictComponent's required field is missing
      assert_raise ArgumentError, "Missing required fields: [:must_have]", fn ->
        Parselet.parse!(text, components: [MultiStrictComponent, MultiLenientComponent])
      end
    end

    test "returns nested results when merge: false" do
      text = """
      Name: John Doe
      Age: 35
      Email: john.doe@example.com

      Street: 123 Main St
      City: Anytown
      """

      result = Parselet.parse(text, components: [PersonalInfoComponent, AddressComponent], merge: false)

      assert is_map(result)
      assert Map.has_key?(result, PersonalInfoComponent)
      assert Map.has_key?(result, AddressComponent)

      personal_info = result[PersonalInfoComponent]
      assert personal_info.name == "John Doe"
      assert personal_info.age == 35
      assert personal_info.email == "john.doe@example.com"

      address_info = result[AddressComponent]
      assert address_info.street == "123 Main St"
      assert address_info.city == "Anytown"
      refute Map.has_key?(address_info, :zip_code)
    end

    test "merge: true is default behavior" do
      defmodule DefaultMergeComponent do
        use Parselet.Component
        field :name, pattern: ~r/Name:\s*(.+)/
        field :age, pattern: ~r/Age:\s*(\d+)/, transform: &String.to_integer/1
      end

      text = "Name: Alice\nAge: 30"
      merged_result = Parselet.parse(text, components: [DefaultMergeComponent])
      explicit_merged_result = Parselet.parse(text, components: [DefaultMergeComponent], merge: true)

      assert merged_result == explicit_merged_result
      assert merged_result.name == "Alice"
      assert merged_result.age == 30
    end

    test "validates required fields in nested results" do
      defmodule NestedRequiredComponent do
        use Parselet.Component
        field :required_data, pattern: ~r/Required:\s*(.+)/, required: true
      end

      defmodule NestedOptionalComponent do
        use Parselet.Component
        field :optional_data, pattern: ~r/Optional:\s*(.+)/
      end

      text = "Optional: Some data"

      assert_raise ArgumentError, "Missing required fields: [:required_data]", fn ->
        Parselet.parse!(text, components: [NestedRequiredComponent, NestedOptionalComponent], merge: false)
      end
    end
  end
end
