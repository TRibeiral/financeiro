defmodule Financeiro.CashFlow do
  import Ecto.Query

  alias Financeiro.Cash
  alias Financeiro.CashFlow.Month
  alias Financeiro.Ledger.Transaction
  alias Financeiro.MonthPeriod
  alias Financeiro.Repo

  @opening_period ~D[2026-07-05]

  def list_rows(today \\ MonthPeriod.current_date()) do
    current_start = MonthPeriod.period_start(today)
    months = Repo.all(from month in Month, order_by: month.period_start)
    first_start = first_period_start(months, current_start)
    period_starts = MonthPeriod.starts_between(first_start, current_start)
    totals = transaction_totals(first_start, MonthPeriod.period_end(current_start))
    months_by_start = Map.new(months, &{&1.period_start, &1})

    {rows, _previous_net} =
      Enum.map_reduce(period_starts, nil, fn period_start, previous_net ->
        month = Map.get(months_by_start, period_start)
        total = Map.get(totals, period_start, %{income: 0, expenses: 0})
        investment_income = value(month, :investment_income_cents, 0)
        capex = value(month, :capex_cents, 0)
        operational_result = total.income - total.expenses
        profit = operational_result + investment_income
        available = value(month, :available_cents)
        obligations = value(month, :obligations_cents)
        net_cash = net_cash(available, obligations)
        net_cash_change = difference(net_cash, previous_net)

        row = %{
          period_start: period_start,
          period_end: MonthPeriod.period_end(period_start),
          current: period_start == current_start,
          opening: period_start == @opening_period,
          income: total.income,
          expenses: total.expenses,
          operational_result: operational_result,
          investment_income: investment_income,
          profit: profit,
          available: available,
          obligations: obligations,
          net_cash: net_cash,
          net_cash_change: net_cash_change,
          capex: capex,
          free_cash_flow: adjusted_cash_generation(net_cash_change, capex, investment_income),
          cash_synced_at: month && month.cash_synced_at
        }

        {row, net_cash}
      end)

    Enum.reverse(rows)
  end

  def get_month(period_start), do: Repo.get_by(Month, period_start: period_start)

  def change_month(period_start, attrs \\ %{}) do
    period_start
    |> get_month()
    |> Kernel.||(%Month{period_start: period_start})
    |> Month.changeset(attrs)
  end

  def save_manual(period_start, attrs) do
    period_start
    |> get_month()
    |> Kernel.||(%Month{period_start: period_start})
    |> Month.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def sync_cash(period_start) do
    summary = Cash.list_balances() |> Cash.summary()

    period_start
    |> get_month()
    |> Kernel.||(%Month{period_start: period_start})
    |> Month.changeset(%{
      available_cents: summary.positive,
      obligations_cents: summary.negative,
      cash_synced_at: DateTime.utc_now(:second)
    })
    |> Repo.insert_or_update()
  end

  defp first_period_start(months, current_start) do
    transaction_start =
      Repo.one(
        from transaction in Transaction,
          where: transaction.flow_type in ["income", "expense", "refund"],
          select: min(transaction.occurred_on)
      )

    first_saved_month =
      case List.first(months) do
        nil -> nil
        month -> month.period_start
      end

    [
      current_start,
      MonthPeriod.history_start(),
      transaction_start && MonthPeriod.period_start(transaction_start),
      first_saved_month
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.min(Date)
  end

  defp transaction_totals(first_start, last_end) do
    Repo.all(
      from transaction in Transaction,
        where:
          transaction.flow_type in ["income", "expense", "refund"] and
            transaction.occurred_on >= ^first_start and transaction.occurred_on <= ^last_end,
        select: {transaction.occurred_on, transaction.flow_type, transaction.amount_cents}
    )
    |> Enum.group_by(fn {date, _flow_type, _amount} -> MonthPeriod.period_start(date) end)
    |> Map.new(fn {period_start, transactions} ->
      income =
        transactions
        |> Enum.filter(fn {_date, flow_type, _amount} -> flow_type == "income" end)
        |> Enum.sum_by(fn {_date, _flow_type, amount} -> amount end)
        |> abs()

      expenses =
        transactions
        |> Enum.filter(fn {_date, flow_type, _amount} -> flow_type in ["expense", "refund"] end)
        |> Enum.sum_by(fn {_date, _flow_type, amount} -> amount end)

      {period_start, %{income: income, expenses: expenses}}
    end)
  end

  defp value(nil, _field, default), do: default
  defp value(struct, field, _default), do: Map.fetch!(struct, field)
  defp value(struct, field), do: value(struct, field, nil)

  defp net_cash(available, obligations) when is_integer(available) and is_integer(obligations),
    do: available + obligations

  defp net_cash(_available, _obligations), do: nil

  defp difference(value, previous) when is_integer(value) and is_integer(previous),
    do: value - previous

  defp difference(_value, _previous), do: nil

  defp adjusted_cash_generation(net_cash_change, capex, investment_income)
       when is_integer(net_cash_change),
       do: net_cash_change + capex - investment_income

  defp adjusted_cash_generation(_net_cash_change, _capex, _investment_income), do: nil
end
