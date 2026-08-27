defmodule Financeiro.InvestmentsTest do
  use Financeiro.DataCase

  alias Financeiro.Investments

  test "computes holding values and portfolio percentages from the latest quote" do
    {:ok, petrobras} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "petr4.sa",
        shares: 100,
        tier: 4,
        last_result: "2/26"
      })

    {:ok, _vale} =
      Investments.create_stock(%{
        name: "Vale",
        ticker: "VALE3",
        shares: 50,
        tier: 3,
        last_result: "2T26"
      })

    assert petrobras.ticker == "PETR4"
    assert petrobras.last_result == "2T26"

    assert {:ok, 2} =
             Investments.apply_quotes([
               %{ticker: "PETR4", price_cents: 3_000, source: "B3"},
               %{ticker: "VALE3", price_cents: 6_000, source: "B3"}
             ])

    [petrobras, vale] = Investments.list_stocks()
    assert Investments.holding_value(petrobras) == 300_000
    assert Investments.holding_value(vale) == 300_000
    assert Investments.summary([petrobras, vale]).total == 600_000
    assert Investments.percentage(petrobras, 600_000) == 50.0
  end

  test "purchase marks get stronger and reset when a new result is recorded" do
    {:ok, stock} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 4,
        last_result: "1T26"
      })

    stock =
      Enum.reduce(1..7, stock, fn _, current ->
        {:ok, updated} = Investments.record_purchase(current)
        updated
      end)

    assert stock.purchase_heat == 7

    {:ok, stock} = Investments.remove_purchase(stock)
    assert stock.purchase_heat == 6

    {:ok, stock} = Investments.update_stock(stock, %{"last_result" => "2T26"})
    assert stock.purchase_heat == 0
    assert stock.tier == 4
  end

  test "purchase marks cannot be reduced below zero" do
    {:ok, stock} =
      Investments.create_stock(%{name: "Petrobras", ticker: "PETR4", shares: 100, tier: 4})

    assert {:ok, stock} = Investments.remove_purchase(stock)
    assert stock.purchase_heat == 0
  end

  test "separates positions from watched stocks in the summary" do
    {:ok, owned} =
      Investments.create_stock(%{name: "Petrobras", ticker: "PETR4", shares: 1, tier: 5})

    {:ok, watched} =
      Investments.create_stock(%{name: "Vale", ticker: "VALE3", shares: 0, tier: 1})

    assert Investments.summary([owned, watched]) |> Map.take([:owned, :watched]) == %{
             owned: 1,
             watched: 1
           }
  end
end
