defmodule Financeiro.Investments.LunaQuoteProviderTest do
  use ExUnit.Case, async: true

  alias Financeiro.Investments.LunaQuoteProvider

  defmodule QuoteRunnerStub do
    def run(prompt, opts) do
      send(self(), {:runner_call, prompt, opts})

      {:ok,
       [
         %{"ticker" => "PETR4", "price_brl" => 37.5, "source" => "B3 · tempo real"}
       ]}
    end
  end

  defmodule BatchRunnerStub do
    def run(prompt, _opts) do
      tickers = Regex.scan(~r/\b[A-Z]{4}\d{1,2}\b/, prompt) |> List.flatten() |> Enum.uniq()

      if length(tickers) <= 2 do
        {:ok,
         Enum.map(tickers, fn ticker ->
           %{"ticker" => ticker, "price_brl" => 10.0, "source" => "B3"}
         end)}
      else
        {:error, "batch too large"}
      end
    end
  end

  test "uses the shared Codex runner with live search and the quote schema" do
    assert {:ok, [%{ticker: "PETR4", price_cents: 3_750, source: "B3 · tempo real"}]} =
             LunaQuoteProvider.fetch_quotes(["PETR4"], runner: QuoteRunnerStub)

    assert_received {:runner_call, prompt, opts}
    assert prompt =~ "PETR4"
    assert opts[:web_search] == true
    assert opts[:output_key] == "quotes"
    assert String.ends_with?(opts[:output_schema], "priv/stock_quotes.schema.json")
  end

  test "splits a large radar into complete validated batches" do
    tickers = ~w(PETR4 VALE3 WEGE3 RADL3 FLRY3)

    assert {:ok, quotes} =
             LunaQuoteProvider.fetch_quotes(tickers,
               runner: BatchRunnerStub,
               batch_size: 2,
               max_concurrency: 2
             )

    assert Enum.sort(Enum.map(quotes, & &1.ticker)) == Enum.sort(tickers)
  end
end
