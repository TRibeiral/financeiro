defmodule Financeiro.Investments.YahooQuoteProviderTest do
  use ExUnit.Case, async: true

  alias Financeiro.Investments.YahooQuoteProvider

  test "fetches all tickers in one request and decodes the latest values" do
    request = fn url, opts ->
      send(self(), {:request, url, opts})

      {:ok,
       %{
         status: 200,
         body: %{
           "PETR4.SA" => %{"timestamp" => [1_788_293_146], "close" => [46.87]},
           "PRIO3.SA" => %{"timestamp" => [1_788_293_144], "close" => [63.99]}
         }
       }}
    end

    assert {:ok, quotes, []} =
             YahooQuoteProvider.fetch_quotes(["PETR4", "PRIO3"], request: request)

    assert_received {:request, url, opts}
    assert url == "https://query2.finance.yahoo.com/v8/finance/spark"
    assert opts[:params][:symbols] == "PETR4.SA,PRIO3.SA"
    assert opts[:params][:range] == "1d"
    assert opts[:params][:interval] == "1d"

    assert Enum.map(quotes, &{&1.ticker, &1.price_cents}) == [
             {"PETR4", 4_687},
             {"PRIO3", 6_399}
           ]

    assert Enum.all?(quotes, &(&1.source == "Yahoo Finance · atraso de 15 min"))
    assert Enum.all?(quotes, &match?(%DateTime{}, &1.quoted_at))
  end

  test "returns successful quotes together with each missing ticker" do
    request = fn _url, _opts ->
      {:ok,
       %{
         status: 200,
         body: %{
           "PETR4.SA" => %{"timestamp" => [1_788_293_146], "close" => [46.87]},
           "VALE3.SA" => %{"timestamp" => [], "close" => []}
         }
       }}
    end

    assert {:ok, [%{ticker: "PETR4"}], [{"VALE3", "cotação não encontrada"}]} =
             YahooQuoteProvider.fetch_quotes(["PETR4", "VALE3"], request: request)
  end

  test "identifies every ticker when a batch request fails" do
    request = fn _url, _opts -> {:ok, %{status: 429, body: "Too Many Requests"}} end

    assert {:ok, [], failures} =
             YahooQuoteProvider.fetch_quotes(["PETR4", "VALE3"], request: request)

    assert failures == [
             {"PETR4", "Yahoo Finance respondeu HTTP 429"},
             {"VALE3", "Yahoo Finance respondeu HTTP 429"}
           ]
  end
end
