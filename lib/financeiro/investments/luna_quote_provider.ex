defmodule Financeiro.Investments.LunaQuoteProvider do
  @moduledoc "Fetches current B3 quotes with Codex Luna through the user's ChatGPT sign-in."

  alias Financeiro.CodexRunner

  def fetch_quotes([]), do: {:ok, []}

  def fetch_quotes(tickers), do: fetch_quotes(tickers, [])

  def fetch_quotes([], _opts), do: {:ok, []}

  def fetch_quotes(tickers, opts) do
    schema = Application.app_dir(:financeiro, "priv/stock_quotes.schema.json")
    runner = Keyword.get(opts, :runner, Application.fetch_env!(:financeiro, :codex_runner))
    timeout_seconds = Keyword.get(opts, :timeout_seconds, 180)
    batch_size = Keyword.get(opts, :batch_size, 10)
    batches = Enum.chunk_every(tickers, batch_size)

    result =
      case batches do
        [batch] ->
          fetch_batch(batch, runner, schema, timeout_seconds)

        batches ->
          batches
          |> Task.async_stream(
            &fetch_batch(&1, runner, schema, timeout_seconds),
            max_concurrency: Keyword.get(opts, :max_concurrency, 3),
            ordered: false,
            timeout: (timeout_seconds + 5) * 1_000,
            on_timeout: :kill_task
          )
          |> collect_batches()
      end

    with {:ok, quotes} <- result,
         {:ok, normalized} <- decode_output(quotes, tickers) do
      {:ok, normalized}
    end
  end

  defp fetch_batch(tickers, runner, schema, timeout_seconds) do
    prompt = prompt(tickers)

    runner.run(prompt,
      output_schema: schema,
      output_key: "quotes",
      web_search: true,
      timeout_seconds: timeout_seconds
    )
  end

  defp prompt(tickers) do
    """
    Pesquise na web a cotação mais recente disponível, em reais, de cada ação da B3 abaixo:
    #{Enum.join(tickers, ", ")}.

    Regras obrigatórias:
    - Retorne exatamente um item para cada ticker e não invente tickers.
    - Use o preço da ação negociada na B3, não ADR, opção, unit ou preço-alvo.
    - Prefira cotação em tempo real; quando indisponível, use o último fechamento.
    - Em source, informe de forma curta o provedor consultado e se é tempo real ou fechamento.
    - Responda somente no JSON Schema fornecido.
    """
  end

  defp collect_batches(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, {:ok, quotes}}, {:ok, acc} -> {:cont, {:ok, quotes ++ acc}}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, "lote de cotações falhou: #{inspect(reason)}"}}
    end)
  end

  def model, do: CodexRunner.model()

  defp decode_output(quotes, expected_tickers) do
    expected = MapSet.new(expected_tickers)

    with {:ok, normalized} <- normalize_quotes(quotes),
         true <- length(normalized) == MapSet.size(expected),
         true <- MapSet.new(Enum.map(normalized, & &1.ticker)) == expected do
      {:ok, normalized}
    else
      _ -> {:error, "Luna não retornou uma cotação válida para cada ticker"}
    end
  end

  defp normalize_quotes(quotes) do
    Enum.reduce_while(quotes, {:ok, []}, fn quote, {:ok, acc} ->
      ticker = quote["ticker"] |> to_string() |> String.upcase() |> String.replace(".SA", "")
      price = quote["price_brl"]
      source = quote["source"]

      if is_number(price) and price > 0 and is_binary(source) do
        {:cont, {:ok, [%{ticker: ticker, price_cents: round(price * 100), source: source} | acc]}}
      else
        {:halt, {:error, :invalid_quote}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end
end
