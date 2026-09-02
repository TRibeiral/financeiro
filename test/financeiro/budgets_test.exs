defmodule Financeiro.BudgetsTest do
  use Financeiro.DataCase

  alias Financeiro.Budgets
  alias Financeiro.Ledger.Transaction
  alias Financeiro.Repo

  test "uses the default budget and carries each net difference into the next month" do
    transaction_fixture(~D[2026-09-04], "expense", 5_000_000)
    transaction_fixture(~D[2026-09-05], "expense", 6_000_000)

    assert {:ok, _month} = Budgets.set_budget(~D[2026-09-05], "70.000,00")

    [october, september, august] = Budgets.list_rows(~D[2026-10-06])

    assert august.budget == 5_500_000
    assert august.expenses == 5_000_000
    assert august.monthly_remaining == 500_000
    assert august.rollover_from_previous == 0
    assert august.rollover_remaining == 500_000
    refute august.custom_budget

    assert september.budget == 7_000_000
    assert september.expenses == 6_000_000
    assert september.monthly_remaining == 1_000_000
    assert september.rollover_from_previous == 500_000
    assert september.rollover_budget == 7_500_000
    assert september.rollover_remaining == 1_500_000
    assert september.custom_budget

    assert october.current
    assert october.expenses == 0
    assert october.budget == 5_500_000
    assert october.rollover_from_previous == 1_500_000
    assert october.rollover_budget == 7_000_000
    assert october.rollover_remaining == 7_000_000
  end

  test "overspending rolls a negative balance forward and refunds reduce expenses" do
    transaction_fixture(~D[2026-08-20], "expense", 6_000_000)
    transaction_fixture(~D[2026-08-21], "refund", -500_000)
    transaction_fixture(~D[2026-09-05], "expense", 5_750_000)

    [september, august] = Budgets.list_rows(~D[2026-09-06])

    assert august.expenses == 5_500_000
    assert august.rollover_remaining == 0
    assert september.monthly_remaining == -250_000
    assert september.rollover_from_previous == 0
    assert september.rollover_remaining == -250_000
  end

  test "a monthly override can be restored to the default" do
    assert {:ok, month} = Budgets.set_budget(~D[2026-08-05], "60.000,00")
    assert month.amount_cents == 6_000_000

    assert {:ok, _month} = Budgets.reset_budget(~D[2026-08-05])

    [august] = Budgets.list_rows(~D[2026-08-20])
    assert august.budget == Budgets.default_monthly_budget_cents()
    refute august.custom_budget
  end

  test "rejects invalid and negative budget values" do
    assert :error = Budgets.set_budget(~D[2026-08-05], "not money")
    assert {:error, changeset} = Budgets.set_budget(~D[2026-08-05], "-1")
    assert "must be greater than or equal to 0" in errors_on(changeset).amount_cents
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
      fingerprint: "budget-#{unique}"
    })
    |> Repo.insert!()
  end
end
