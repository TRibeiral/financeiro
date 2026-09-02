defmodule Financeiro.Investments.YahooQuoteProvider do
  @moduledoc "Fetches delayed B3 quotes from Yahoo Finance in batches."

  @endpoint "https://query2.finance.yahoo.com/v8/finance/spark"
  @batch_size 20
  @source "Yahoo Finance · atraso de 15 min"

  def fetch_quotes(tickers), do: fetch_quotes(tickers, [])

  def fetch_quotes(tickers, opts) when is_list(tickers) do
    request = Keyword.get(opts, :request, &Req.get/2)

    tickers
    |> Enum.map(&normalize_ticker/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.chunk_every(Keyword.get(opts, :batch_size, @batch_size))
    |> Enum.reduce({[], []}, fn batch, {quotes, failures} ->
      case fetch_batch(batch, request) do
        {:ok, batch_quotes, batch_failures} ->
          {quotes ++ batch_quotes, failures ++ batch_failures}

        {:error, reason} ->
          {quotes, failures ++ Enum.map(batch, &{&1, reason})}
      end
    end)
    |> then(fn {quotes, failures} -> {:ok, quotes, failures} end)
  end

  defp fetch_batch([], _request), do: {:ok, [], []}

  defp fetch_batch(tickers, request) do
    symbols = Enum.map_join(tickers, ",", &yahoo_symbol/1)

    options = [
      params: [symbols: symbols, range: "1d", interval: "1d"],
      headers: [{"user-agent", "Mozilla/5.0 Financeiro/1.0"}],
      receive_timeout: 10_000,
      retry: :transient,
      max_retries: 2
    ]

    case request.(@endpoint, options) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        decode_batch(body, tickers)

      {:ok, %{status: status}} ->
        {:error, "Yahoo Finance respondeu HTTP #{status}"}

      {:error, reason} ->
        {:error, "Yahoo Finance indisponível: #{format_reason(reason)}"}

      other ->
        {:error, "resposta inesperada do Yahoo Finance: #{inspect(other)}"}
    end
  end

  defp decode_batch(body, tickers) do
    {quotes, failures} =
      Enum.reduce(tickers, {[], []}, fn ticker, {quotes, failures} ->
        case decode_quote(body[yahoo_symbol(ticker)], ticker) do
          {:ok, quote} -> {[quote | quotes], failures}
          {:error, reason} -> {quotes, [{ticker, reason} | failures]}
        end
      end)

    {:ok, Enum.reverse(quotes), Enum.reverse(failures)}
  end

  defp decode_quote(%{"timestamp" => timestamps, "close" => prices}, ticker)
       when is_list(timestamps) and is_list(prices) do
    timestamps
    |> Enum.zip(prices)
    |> Enum.reverse()
    |> Enum.find(fn {timestamp, price} ->
      is_integer(timestamp) and is_number(price) and price > 0
    end)
    |> case do
      {timestamp, price} ->
        with {:ok, quoted_at} <- DateTime.from_unix(timestamp) do
          {:ok,
           %{
             ticker: ticker,
             price_cents: round(price * 100),
             source: @source,
             quoted_at: DateTime.truncate(quoted_at, :second)
           }}
        else
          _ -> {:error, "horário da cotação inválido"}
        end

      nil ->
        {:error, "cotação não encontrada"}
    end
  end

  defp decode_quote(_payload, _ticker), do: {:error, "cotação não encontrada"}

  defp normalize_ticker(ticker) do
    ticker
    |> to_string()
    |> String.trim()
    |> String.upcase()
    |> String.replace_suffix(".SA", "")
  end

  defp yahoo_symbol(ticker), do: ticker <> ".SA"

  defp format_reason(%{reason: reason}), do: to_string(reason)
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
