defmodule FinanceiroWeb.Format do
  def money(cents) when is_integer(cents) do
    sign = if cents < 0, do: "−", else: ""
    absolute = abs(cents)
    whole = div(absolute, 100) |> Integer.to_string() |> group_thousands()
    decimal = rem(absolute, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}R$ #{whole},#{decimal}"
  end

  def date(%Date{} = date) do
    "#{pad(date.day)}/#{pad(date.month)}/#{date.year}"
  end

  def short_date(%Date{} = date), do: "#{pad(date.day)}/#{pad(date.month)}"

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp group_thousands(value) do
    value
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(".", &Enum.join/1)
    |> String.reverse()
  end
end
