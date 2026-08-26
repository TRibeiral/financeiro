defmodule Financeiro.FakeStockQuoteProvider do
  def fetch_quotes(tickers) do
    {:ok,
     Enum.map(tickers, fn ticker ->
       %{ticker: ticker, price_cents: price_for(ticker), source: "Cotação de teste"}
     end)}
  end

  defp price_for("PETR4"), do: 3_750
  defp price_for("VALE3"), do: 6_420
  defp price_for(_ticker), do: 1_000
end
