defmodule Financeiro.CashTest do
  use Financeiro.DataCase

  alias Financeiro.Cash

  test "stores positive and negative balances in cents and summarizes the net cash" do
    assert {:ok, account} = Cash.create_balance(%{name: "Nubank", amount: "1.234,56"})
    assert account.amount_cents == 123_456

    assert {:ok, card} = Cash.create_balance(%{name: "Cartão Itaú", amount: "-450.90"})
    assert card.amount_cents == -45_090

    assert Cash.summary(Cash.list_balances()) == %{
             total: 78_366,
             positive: 123_456,
             negative: -45_090,
             count: 2
           }
  end

  test "requires a name and a valid amount" do
    assert {:error, changeset} = Cash.create_balance(%{name: "", amount: "12.345"})
    assert "can't be blank" in errors_on(changeset).name
    assert "use um valor como 1250,00 ou -450,90" in errors_on(changeset).amount
  end
end
