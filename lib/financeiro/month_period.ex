defmodule Financeiro.MonthPeriod do
  @moduledoc "Defines financial months that run from the 5th through the 4th."

  @start_day 5
  @history_start ~D[2026-08-05]

  def history_start, do: @history_start

  def current_date do
    DateTime.utc_now()
    |> DateTime.add(-3 * 60 * 60, :second)
    |> DateTime.to_date()
  end

  def current_bounds, do: bounds(current_date())

  def period_start(%Date{} = date), do: date |> bounds() |> elem(0)

  def period_end(%Date{} = period_start) do
    Date.add(period_start, Date.days_in_month(period_start) - 1)
  end

  def starts_between(%Date{} = first_start, %Date{} = last_start) do
    Stream.iterate(first_start, &next_start/1)
    |> Enum.take_while(&(Date.compare(&1, last_start) != :gt))
  end

  def previous_start(%Date{} = period_start), do: period_start |> Date.add(-1) |> period_start()

  def bounds(%Date{} = date) do
    period_month =
      if date.day >= @start_day do
        Date.beginning_of_month(date)
      else
        date |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()
      end

    period_start = Date.new!(period_month.year, period_month.month, @start_day)
    period_end = Date.add(period_start, Date.days_in_month(period_start) - 1)

    {period_start, period_end}
  end

  def filters(date \\ current_date()) do
    {period_start, period_end} = bounds(date)

    %{
      "from" => Date.to_iso8601(period_start),
      "to" => Date.to_iso8601(period_end)
    }
  end

  defp next_start(period_start), do: Date.add(period_start, Date.days_in_month(period_start))
end
