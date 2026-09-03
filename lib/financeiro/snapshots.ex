defmodule Financeiro.Snapshots do
  import Ecto.Query

  alias Financeiro.Cash
  alias Financeiro.Investments
  alias Financeiro.Repo
  alias Financeiro.Snapshots.{Item, Snapshot}

  def list_snapshots do
    Snapshot
    |> order_by(desc: :captured_at, desc: :id)
    |> preload(items: ^from(i in Item, order_by: [asc: i.category, desc: i.value_cents]))
    |> Repo.all()
  end

  def capture_current do
    Repo.transaction(fn ->
      captured_at = DateTime.utc_now() |> DateTime.truncate(:second)
      cash = Cash.list_balances()
      stocks = Investments.list_stocks() |> Enum.filter(&(&1.shares > 0))
      other_investments = Investments.list_other_investments()

      cash_total = Enum.sum(Enum.map(cash, & &1.amount_cents))
      stocks_total = Enum.sum(Enum.map(stocks, &Investments.holding_value/1))
      other_total = Enum.sum(Enum.map(other_investments, & &1.value_cents))

      snapshot_attrs = %{
        captured_at: captured_at,
        total_cents: cash_total + stocks_total + other_total,
        cash_cents: cash_total,
        stocks_cents: stocks_total,
        other_investments_cents: other_total,
        cash_count: length(cash),
        stocks_count: length(stocks),
        other_investments_count: length(other_investments),
        stocks_without_quote_count: Enum.count(stocks, &is_nil(&1.quote_cents))
      }

      snapshot =
        %Snapshot{}
        |> Snapshot.changeset(snapshot_attrs)
        |> Repo.insert!()

      items =
        Enum.map(cash, fn balance ->
          item(snapshot, captured_at, "cash", balance.name, balance.amount_cents, balance.id)
        end) ++
          Enum.map(stocks, fn stock ->
            item(
              snapshot,
              captured_at,
              "stocks",
              stock.name,
              Investments.holding_value(stock),
              stock.id,
              ticker: stock.ticker,
              shares: stock.shares,
              quote_cents: stock.quote_cents
            )
          end) ++
          Enum.map(other_investments, fn investment ->
            item(
              snapshot,
              captured_at,
              "other_investments",
              investment.description,
              investment.value_cents,
              investment.id
            )
          end)

      Repo.insert_all(Item, items)
      Repo.preload(snapshot, :items)
    end)
  end

  def current_preview do
    cash = Cash.list_balances()
    stocks = Investments.list_stocks() |> Enum.filter(&(&1.shares > 0))
    other_investments = Investments.list_other_investments()

    cash_cents = Enum.sum(Enum.map(cash, & &1.amount_cents))
    stocks_cents = Enum.sum(Enum.map(stocks, &Investments.holding_value/1))
    other_investments_cents = Enum.sum(Enum.map(other_investments, & &1.value_cents))

    %{
      cash_cents: cash_cents,
      stocks_cents: stocks_cents,
      other_investments_cents: other_investments_cents,
      total_cents: cash_cents + stocks_cents + other_investments_cents,
      item_count: length(cash) + length(stocks) + length(other_investments),
      stocks_without_quote_count: Enum.count(stocks, &is_nil(&1.quote_cents))
    }
  end

  defp item(snapshot, now, category, name, value_cents, source_id, details \\ []) do
    %{
      snapshot_id: snapshot.id,
      category: category,
      name: name,
      value_cents: value_cents,
      source_id: source_id,
      ticker: details[:ticker],
      shares: details[:shares],
      quote_cents: details[:quote_cents],
      inserted_at: now,
      updated_at: now
    }
  end
end
