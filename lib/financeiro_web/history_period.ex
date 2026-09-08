defmodule FinanceiroWeb.HistoryPeriod do
  @moduledoc false

  alias Financeiro.MonthPeriod
  alias FinanceiroWeb.Format

  def options,
    do: [{"all", "Todo o histórico"}, {"current", "Mês atual"}, {"previous", "Mês anterior"}]

  def filters("current"), do: MonthPeriod.filters()

  def filters("previous") do
    current_start = MonthPeriod.current_bounds() |> elem(0)
    previous_start = MonthPeriod.previous_start(current_start)

    %{
      "from" => Date.to_iso8601(previous_start),
      "to" => Date.to_iso8601(MonthPeriod.period_end(previous_start))
    }
  end

  def filters(_all), do: %{"from" => "", "to" => ""}

  def selected(filters) do
    from = Map.get(filters, "from", "")
    to = Map.get(filters, "to", "")
    current = filters("current")
    previous = filters("previous")

    key =
      cond do
        from == "" and to == "" -> "all"
        from == current["from"] and to == current["to"] -> "current"
        from == previous["from"] and to == previous["to"] -> "previous"
        true -> "custom"
      end

    %{key: key, from: parse_date(from), to: parse_date(to)}
  end

  def label(%{key: "all"}), do: "Todo o histórico"

  def label(%{key: "current", from: from_date, to: to_date}),
    do: "Mês financeiro atual · #{Format.short_date(from_date)} a #{Format.short_date(to_date)}"

  def label(%{key: "previous", from: from_date, to: to_date}),
    do:
      "Mês financeiro anterior · #{Format.short_date(from_date)} a #{Format.short_date(to_date)}"

  def label(%{from: from_date, to: to_date}) do
    "Período personalizado · #{date_boundary(from_date, "início")} a #{date_boundary(to_date, "hoje")}"
  end

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_value), do: nil

  defp date_boundary(nil, fallback), do: fallback
  defp date_boundary(date, _fallback), do: Format.short_date(date)
end
