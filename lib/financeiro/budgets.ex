defmodule Financeiro.Budgets do
  @moduledoc "Monthly spending budgets and their accumulated rollover."

  import Ecto.Query

  alias Financeiro.Budgets.Month
  alias Financeiro.Ledger.Transaction
  alias Financeiro.MoneyInput
  alias Financeiro.MonthPeriod
  alias Financeiro.Repo

  @default_monthly_budget_cents 5_500_000

  def default_monthly_budget_cents, do: @default_monthly_budget_cents

  def list_rows(today \\ MonthPeriod.current_date()) do
    current_start = MonthPeriod.period_start(today)
    months = Repo.all(from month in Month, order_by: month.period_start)
    first_start = first_period_start(months, current_start)
    last_start = last_period_start(months, current_start)
    totals = expense_totals(first_start, MonthPeriod.period_end(last_start))
    months_by_start = Map.new(months, &{&1.period_start, &1})

    {rows, _rollover} =
      first_start
      |> MonthPeriod.starts_between(last_start)
      |> Enum.map_reduce(0, fn period_start, rollover ->
        month = Map.get(months_by_start, period_start)
        budget = if month, do: month.amount_cents, else: @default_monthly_budget_cents
        expenses = Map.get(totals, period_start, 0)
        monthly_remaining = budget - expenses
        rollover_budget = budget + rollover
        rollover_remaining = rollover_budget - expenses

        row = %{
          period_start: period_start,
          period_end: MonthPeriod.period_end(period_start),
          current: period_start == current_start,
          future: Date.compare(period_start, current_start) == :gt,
          custom_budget: not is_nil(month),
          budget: budget,
          expenses: expenses,
          monthly_remaining: monthly_remaining,
          rollover_from_previous: rollover,
          rollover_budget: rollover_budget,
          rollover_remaining: rollover_remaining
        }

        {row, rollover_remaining}
      end)

    Enum.reverse(rows)
  end

  def get_month(period_start), do: Repo.get_by(Month, period_start: period_start)

  def set_budget(%Date{} = period_start, input) do
    with {:ok, amount_cents} <- MoneyInput.parse(input) do
      period_start
      |> get_month()
      |> Kernel.||(%Month{period_start: period_start})
      |> Month.changeset(%{amount_cents: amount_cents})
      |> Repo.insert_or_update()
    end
  end

  def reset_budget(%Date{} = period_start) do
    case get_month(period_start) do
      nil -> {:ok, nil}
      month -> Repo.delete(month)
    end
  end

  defp first_period_start(months, current_start) do
    transaction_start =
      Repo.one(
        from transaction in Transaction,
          where: transaction.flow_type in ["expense", "refund"],
          select: min(transaction.occurred_on)
      )

    [
      current_start,
      MonthPeriod.history_start(),
      transaction_start && MonthPeriod.period_start(transaction_start),
      months |> List.first() |> month_start()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(Date)
  end

  defp last_period_start(months, current_start) do
    [current_start, months |> List.last() |> month_start()]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(Date)
  end

  defp month_start(nil), do: nil
  defp month_start(month), do: month.period_start

  defp expense_totals(first_start, last_end) do
    Repo.all(
      from transaction in Transaction,
        where:
          transaction.flow_type in ["expense", "refund"] and
            transaction.occurred_on >= ^first_start and transaction.occurred_on <= ^last_end,
        select: {transaction.occurred_on, transaction.amount_cents}
    )
    |> Enum.group_by(fn {date, _amount} -> MonthPeriod.period_start(date) end)
    |> Map.new(fn {period_start, transactions} ->
      {period_start, Enum.sum_by(transactions, fn {_date, amount} -> amount end)}
    end)
  end
end
