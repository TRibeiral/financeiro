defmodule Financeiro.SnapshotsTest do
  use Financeiro.DataCase

  alias Financeiro.Cash
  alias Financeiro.Investments
  alias Financeiro.Snapshots

  test "captures category totals and immutable source rows" do
    assert {:ok, account} =
             Cash.create_balance(%{name: "Conta principal", amount: "1500,00"})

    assert {:ok, _card} = Cash.create_balance(%{name: "Cartão", amount: "-250,00"})

    assert {:ok, _property} =
             Investments.create_other_investment(%{
               description: "Apartamento",
               value: "500000,00"
             })

    assert {:ok, stock} =
             Investments.create_stock(%{
               name: "Petrobras",
               ticker: "PETR4",
               shares: 100,
               last_result: "2T26",
               tier: 1
             })

    assert {:ok, _watched} =
             Investments.create_stock(%{
               name: "Vale",
               ticker: "VALE3",
               shares: 0,
               last_result: "2T26",
               tier: 2
             })

    assert {:ok, 1} =
             Investments.apply_quotes([
               %{ticker: stock.ticker, price_cents: 3_000, source: "test"}
             ])

    assert {:ok, snapshot} = Snapshots.capture_current()
    assert snapshot.cash_cents == 125_000
    assert snapshot.stocks_cents == 300_000
    assert snapshot.other_investments_cents == 50_000_000
    assert snapshot.total_cents == 50_425_000
    assert snapshot.cash_count == 2
    assert snapshot.stocks_count == 1
    assert snapshot.other_investments_count == 1
    assert snapshot.stocks_without_quote_count == 0

    stock_item = Enum.find(snapshot.items, &(&1.category == "stocks"))
    assert stock_item.name == "Petrobras"
    assert stock_item.ticker == "PETR4"
    assert stock_item.shares == 100
    assert stock_item.quote_cents == 3_000
    assert stock_item.value_cents == 300_000

    assert {:ok, _account} = Cash.update_balance(account, %{amount: "2000,00"})
    assert {:ok, newer_snapshot} = Snapshots.capture_current()

    [newest, oldest] = Snapshots.list_snapshots()
    assert newest.id == newer_snapshot.id
    assert newest.cash_cents == 175_000
    assert oldest.id == snapshot.id
    assert oldest.cash_cents == 125_000
    assert Enum.find(oldest.items, &(&1.name == "Conta principal")).value_cents == 150_000
  end

  test "keeps owned stocks without quotes visible at zero" do
    assert {:ok, _stock} =
             Investments.create_stock(%{
               name: "Sem cotação",
               ticker: "SEMC3",
               shares: 25,
               last_result: "2T26",
               tier: 1
             })

    assert {:ok, snapshot} = Snapshots.capture_current()
    assert snapshot.stocks_count == 1
    assert snapshot.stocks_without_quote_count == 1
    assert [%{value_cents: 0, quote_cents: nil}] = snapshot.items
  end
end
