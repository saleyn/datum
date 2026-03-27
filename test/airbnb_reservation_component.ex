defmodule Parselet.Test do
  defmodule Date do
    alias Timex

    def normalize_range([check_in_str, check_out_str]) do
      year = Date.utc_today().year

      {:ok, check_in} =
        Timex.parse("#{check_in_str} #{year}", "{Mshort} {D} {YYYY}")
        |> to_date()

      {:ok, check_out} =
        Timex.parse("#{check_out_str} #{year}", "{Mshort} {D} {YYYY}")
        |> to_date()

      %{
        check_in: check_in,
        check_out: check_out
      }
    end

    defp to_date({:ok, dt}), do: {:ok, Timex.to_date(dt)}
    defp to_date(error), do: error
  end

  defmodule Components.AirbnbReservation do
    use Parselet.Component

    field :reservation_code,
      pattern: ~r/Reservation code[:\s]+([A-Z0-9\-]+)/i,
      capture: :first

    field :guest_name,
      pattern: ~r/(?:You’re hosting|You're hosting|Reservation for)\s+([^\n]+)/i,
      capture: :first,
      transform: &String.trim/1

    field :date_range,
      pattern: ~r/([A-Za-z]{3} \d{1,2})\s*[–-]\s*([A-Za-z]{3} \d{1,2})/,
      capture: :all,
      transform: &Parselet.Test.Date.normalize_range/1

    field :nights,
      pattern: ~r/(\d+)\s+nights?/i,
      capture: :first,
      transform: &String.to_integer/1

    field :guest_count,
      pattern: ~r/(\d+)\s+guests?/i,
      capture: :first,
      transform: &String.to_integer/1

    field :listing_name,
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

    field :check_in_time,
      pattern: ~r/Check-?in[:\s]+\s*([\d:]+\s*[AP]M)/i,
      capture: :first

    field :check_out_time,
      pattern: ~r/Check-?out[:\s]+\s*([\d:]+\s*[AP]M)/i,
      capture: :first

    field :payout_amount,
      pattern: ~r/(?:Your earnings|Payout)[:\s]+\$([\d,]+\.\d{2})/i,
      capture: :first,
      transform: fn amt ->
        amt
        |> String.replace(",", "")
        |> String.to_float()
      end
  end

  defmodule Parser do
    use Parselet.Parser

      @reservation_markers [
      "You’re hosting",
      "You're hosting",
      "Reservation confirmed",
      "Reservation for"
    ]

    def parse(email_text) do
      case classify(email_text) do
        :reservation ->
          Parselet.parse(email_text, components: [AirbnbReservation])

        :unknown ->
          {:error, :unknown_airbnb_email_type}
      end
    end

    defp classify(text) do
      if Enum.any?(@reservation_markers, &String.contains?(text, &1)) do
        :reservation
      else
        :unknown
      end
    end
  end
end
