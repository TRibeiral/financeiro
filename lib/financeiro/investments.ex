defmodule Financeiro.Investments do
  import Ecto.Query

  alias Financeiro.Investments.Stock
  alias Financeiro.Repo

  @current_result "2T26"

  def current_result, do: @current_result

  def list_stocks do
    Repo.all(from s in Stock, order_by: [desc: s.shares, desc: s.tier, asc: s.name])
  end

  def get_stock!(id), do: Repo.get!(Stock, id)
  def change_stock(stock, attrs \\ %{}), do: Stock.changeset(stock, attrs)

  def create_stock(attrs) do
    %Stock{}
    |> Stock.changeset(attrs)
    |> Repo.insert()
  end

  def update_stock(%Stock{} = stock, attrs) do
    changeset = Stock.changeset(stock, attrs)

    changeset =
      if Ecto.Changeset.get_change(changeset, :last_result) do
        Ecto.Changeset.put_change(changeset, :purchase_heat, 0)
      else
        changeset
      end

    Repo.update(changeset)
  end

  def record_purchase(%Stock{} = stock) do
    stock
    |> Ecto.Changeset.change(purchase_heat: min(stock.purchase_heat + 1, 5))
    |> Repo.update()
  end

  def check_today(%Stock{} = stock) do
    stock |> Ecto.Changeset.change(checked_on: Date.utc_today()) |> Repo.update()
  end

  def apply_quotes(quotes) when is_list(quotes) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Enum.reduce(quotes, 0, fn quote, count ->
        ticker = quote[:ticker] || quote["ticker"]
        price_cents = quote[:price_cents] || quote["price_cents"]
        source = quote[:source] || quote["source"]

        if is_binary(ticker) and is_integer(price_cents) and price_cents > 0 do
          {updated, _} =
            from(s in Stock, where: s.ticker == ^String.upcase(ticker))
            |> Repo.update_all(
              set: [
                quote_cents: price_cents,
                quote_source: source,
                quote_refreshed_at: now,
                updated_at: now
              ]
            )

          count + updated
        else
          count
        end
      end)
    end)
  end

  def holding_value(%Stock{shares: shares, quote_cents: quote_cents})
      when is_integer(quote_cents),
      do: shares * quote_cents

  def holding_value(_stock), do: 0

  def summary(stocks) do
    total = Enum.reduce(stocks, 0, &(holding_value(&1) + &2))
    owned = Enum.count(stocks, &(&1.shares > 0))

    %{
      total: total,
      owned: owned,
      watched: Enum.count(stocks, &(&1.shares == 0)),
      current_results: Enum.count(stocks, &(&1.last_result == @current_result)),
      results_to_read: Enum.count(stocks, &(&1.last_result != @current_result)),
      without_quote: Enum.count(stocks, &is_nil(&1.quote_cents))
    }
  end

  def percentage(stock, total) when total > 0,
    do: holding_value(stock) * 100 / total

  def percentage(_stock, _total), do: 0.0
end
