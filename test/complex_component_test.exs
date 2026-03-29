defmodule Parselet.ComplexComponentTest do
  use ExUnit.Case, async: true
  Code.require_file("complex_component.ex", __DIR__)
  alias Parselet.AirbnbReservationComponent

  test "parses airbnb reservation 3 fixture" do
    fixture_path = Path.join([__DIR__, "support", "fixtures", "airbnb_reservation_3.txt"])
    text         = File.read!(fixture_path)
    result       = AirbnbReservationComponent.parse!(text)

    assert result.reservation_code == "FAKECONF1234"
    assert result.guest_name       == "Jamie"
    assert result.check_in_date    == "Sat, Dec 18, 2026"
    assert result.check_out_date   == "Sat, Dec 25, 2026"
    assert result.nights           == 7
    assert result.property_name    == "YOUR GATEWAY HOUSE"
    assert result.guest_count      == 10
    assert result.cleaning_fee     == 150.00
    assert result.check_in_time    == "4:00 PM"
    assert result.check_out_time   == "10:00 AM"
    assert result.earnings         == 2234.38
  end
end
