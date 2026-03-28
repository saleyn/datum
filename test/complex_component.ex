defmodule Parselet.AirbnbReservationComponent do
  use Parselet.Component

  preprocess &normalize_text/1

  field :reservation_code, function: &extract_reservation_code/1
  field :guest_name,       function: &extract_guest_name/1
  field :check_in_date,    function: &extract_check_in_date/1
  field :check_out_date,   function: &extract_check_out_date/1
  field :nights,           pattern:  ~r/(\d+)\s+nights/, capture: :first, transform: &String.to_integer/1
  field :property_name,    function: &extract_property_name/1
  field :guest_count,      pattern:  ~r/(\d+)\s+adults/, capture: :first, transform: &String.to_integer/1
  field :cleaning_fee,     pattern:  ~r/Cleaning fee\s*\$([\d,]+\.\d{2})/i, capture: :first, transform: fn amount -> amount |> String.replace(",", "") |> String.to_float() end
  field :check_in_time,    function: &extract_check_in_time/1
  field :check_out_time,   function: &extract_check_out_time/1
  field :earnings,         function: &extract_earnings/1

  def extract_reservation_code(text) do
    case Regex.run(~r/CONFIRMATION CODE\s*[:\s]*([A-Z0-9]+)/i, text, capture: :all_but_first) do
      [code] -> String.trim(code)
      _ -> nil
    end
  end

  def extract_guest_name(text) do
    patterns = [
      ~r/NEW BOOKING CONFIRMED!\s*([A-Z]+)\s+ARRIVES/i,
      ~r/Send a message .* welcome\s*([A-Z][A-Za-z]+)/i,
      ~r/ARRIVES\s*([A-Z][A-Za-z]+)/i
    ]

    patterns
    |> Enum.find_value(fn regex ->
      case Regex.run(regex, text, capture: :all_but_first) do
        [name] -> String.trim(name)
        _ -> nil
      end
    end)
    |> normalize_guest_name()
  end

  def extract_check_in_date(text) do
    text
    |> parse_booking_dates()
    |> elem(0)
  end

  def extract_check_out_date(text) do
    text
    |> parse_booking_dates()
    |> elem(1)
  end

  def extract_property_name(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      lines when is_list(lines) ->
        lines
        |> Enum.find_index(&String.match?(&1, ~r/^Entire home\/apt$/i))
        |> case do
          nil -> nil
          idx -> Enum.at(lines, idx - 1)
        end
    end
  end

  def extract_check_in_time(text) do
    text
    |> parse_checkin_checkout_times()
    |> elem(0)
  end

  def extract_check_out_time(text) do
    text
    |> parse_checkin_checkout_times()
    |> elem(1)
  end

  def extract_earnings(text) do
    case Regex.run(~r/(?:Your earnings|Payout|YOU EARN)\s*\$([\d,]+\.\d{2})/i, text,
              capture: :all_but_first)
    do
      [amount] -> amount |> String.replace(",", "") |> String.to_float()
      _ -> nil
    end
  end

  def normalize_text(text) do
    text
    |> extract_plain_text_body()
    |> String.replace("\r\n", "\n")
    |> String.replace(~r/=\r?\n/, "")
    |> decode_quoted_printable()
    |> String.replace(~r/[\x{00A0}\x{202F}\x{2009}]/u, " ")
    |> String.replace(~r/\s+\n/, "\n")
  end

  defp extract_plain_text_body(text) do
    case Regex.run(~r/Content-Type: text\/plain; charset=utf-8.*?\r?\n\r?\n(.*?)(?=\r?\n--|\z)/si, text, capture: :all_but_first) do
      [body] -> body
      _ -> text
    end
  end

  defp decode_quoted_printable(text) do
    Regex.replace(~r/=([0-9A-Fa-f]{2})/, text, fn _, hex -> <<String.to_integer(hex, 16)>> end)
  end

  defp normalize_guest_name(nil), do: nil

  defp normalize_guest_name(name) do
    name
    |> String.replace(~r/[^A-Za-z\s'-]/, "")
    |> String.split()
    |> Enum.map(&String.capitalize(String.downcase(&1)))
    |> Enum.join(" ")
  end

  defp parse_booking_dates(text) do
    case Regex.run(~r/Check-in.*?Checkout.*?(\w{3},\s*\w{3}\s+\d{1,2},\s*\d{4})\s+(\w{3},\s*\w{3}\s+\d{1,2},\s*\d{4})/is, text,
          capture: :all_but_first) do
      [check_in, check_out] -> {check_in, check_out}
      _ -> {nil, nil}
    end
  end

  defp parse_checkin_checkout_times(text) do
    case Regex.run(~r/Check-in.*?Checkout.*?([0-9]{1,2}:[0-9]{2}\s*(?:AM|PM)).*?([0-9]{1,2}:[0-9]{2}\s*(?:AM|PM))/is, text,
          capture: :all_but_first) do
      [check_in_time, check_out_time] ->
        {String.trim(check_in_time), String.trim(check_out_time)}

      _ ->
        {nil, nil}
    end
  end
end
