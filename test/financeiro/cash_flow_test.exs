defmodule Financeiro.CashFlowTest do
  use Financeiro.DataCase

  alias Financeiro.CashFlow
  alias Financeiro.CashFlow.Month
  alias Financeiro.Ledger.Transaction
  alias Financeiro.Repo

  test "starts with the July opening position and the current financial month" do
    [row, opening] = CashFlow.list_rows(~D[2026-08-20])

    assert row.period_start == ~D[2026-08-05]
    assert row.current
    assert row.income == 0
    assert row.net_cash == nil

    assert opening.period_start == ~D[2026-07-05]
    assert opening.opening
    assert opening.available == 41_686_255
    assert opening.obligations == -11_658_789
    assert opening.net_cash == 30_027_466
  end

  test "calculates monthly results, the day-five cutoff, net cash change, and FCO" do
    transaction_fixture(~D[2026-09-04], "income", -100_000)
    transaction_fixture(~D[2026-09-04], "expense", 30_000)
    transaction_fixture(~D[2026-09-05], "income", -80_000)
    transaction_fixture(~D[2026-09-05], "expense", 25_000)

    month_fixture(~D[2026-08-05], %{
      available_cents: 200_000,
      obligations_cents: -50_000
    })

    assert {:ok, current} =
             CashFlow.save_manual(~D[2026-09-05], %{
               investment_income_expression: "2+440+59",
               capex_expression: "5000+1200"
             })

    current
    |> Month.changeset(%{available_cents: 260_000, obligations_cents: -50_000})
    |> Repo.update!()

    [september, august | _] = CashFlow.list_rows(~D[2026-09-06])

    assert august.income == 100_000
    assert august.expenses == 30_000
    assert august.operational_result == 70_000
    assert august.net_cash == 150_000

    assert september.income == 80_000
    assert september.expenses == 25_000
    assert september.operational_result == 55_000
    assert september.investment_income == 50_100
    assert september.profit == 105_100
    assert september.net_cash == 210_000
    assert september.net_cash_change == 60_000
    assert september.capex == 620_000
    assert september.free_cash_flow == 629_900
  end

  defp month_fixture(period_start, attrs) do
    %Month{period_start: period_start}
    |> Month.changeset(attrs)
    |> Repo.insert!()
  end

  defp transaction_fixture(date, flow_type, amount_cents) do
    unique = System.unique_integer([:positive])

    %Transaction{}
    |> Transaction.changeset(%{
      occurred_on: date,
      amount_cents: amount_cents,
      description: "Movimento #{unique}",
      merchant_key: "movimento #{unique}",
      flow_type: flow_type,
      category: "Outros",
      review_status: "reviewed",
      bank: "Teste",
      owner: "Thiago",
      source_type: "conta",
      source_file: "teste.csv",
      fingerprint: "cash-flow-#{unique}"
    })
    |> Repo.insert!()
  end
end
