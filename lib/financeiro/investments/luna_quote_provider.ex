defmodule Financeiro.Investments.LunaQuoteProvider do
  @moduledoc "Fetches current B3 quotes with Codex Luna through the user's ChatGPT sign-in."

  @model "gpt-5.6-luna"

  def fetch_quotes([]), do: {:ok, []}

  def fetch_quotes(tickers) do
    codex = Application.get_env(:financeiro, :codex_executable, "codex")
    schema = Application.app_dir(:financeiro, "priv/stock_quotes.schema.json")

    output =
      Path.join(System.tmp_dir!(), "financeiro-quotes-#{System.unique_integer([:positive])}.json")

    prompt = """
    Pesquise na web a cotação mais recente disponível, em reais, de cada ação da B3 abaixo:
    #{Enum.join(tickers, ", ")}.

    Regras obrigatórias:
    - Retorne exatamente um item para cada ticker e não invente tickers.
    - Use o preço da ação negociada na B3, não ADR, opção, unit ou preço-alvo.
    - Prefira cotação em tempo real; quando indisponível, use o último fechamento.
    - Em source, informe de forma curta o provedor consultado e se é tempo real ou fechamento.
    - Responda somente no JSON Schema fornecido.
    """

    args = [
      "exec",
      "--model",
      @model,
      "--sandbox",
      "read-only",
      "--ephemeral",
      "--skip-git-repo-check",
      "--color",
      "never",
      "--output-schema",
      schema,
      "--output-last-message",
      output,
      "-c",
      ~s(forced_login_method="chatgpt"),
      "-C",
      System.tmp_dir!(),
      prompt
    ]

    try do
      timeout = System.find_executable("timeout")

      {command, command_args} =
        if timeout, do: {timeout, ["180s", codex | args]}, else: {codex, args}

      shell = System.find_executable("sh") || "/bin/sh"

      case System.cmd(
             shell,
             ["-c", ~s(exec "$@" </dev/null), "financeiro-quotes", command | command_args],
             stderr_to_stdout: true,
             env: [{"OPENAI_API_KEY", nil}],
             into: ""
           ) do
        {_log, 0} -> decode_output(output, tickers)
        {log, status} -> {:error, "Luna terminou com status #{status}: #{compact(log)}"}
      end
    rescue
      error in ErlangError ->
        {:error, "não foi possível executar o Codex CLI: #{Exception.message(error)}"}
    after
      File.rm(output)
    end
  end

  def model, do: @model

  defp decode_output(path, expected_tickers) do
    expected = MapSet.new(expected_tickers)

    with {:ok, body} <- File.read(path),
         {:ok, %{"quotes" => quotes}} when is_list(quotes) <- Jason.decode(body),
         {:ok, normalized} <- normalize_quotes(quotes),
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

  defp compact(text),
    do: text |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 500)
end
