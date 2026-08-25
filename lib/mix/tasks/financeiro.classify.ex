defmodule Mix.Tasks.Financeiro.Classify do
  use Mix.Task

  @shortdoc "Classifica pendências com GPT-5.6 Luna pelo Codex da assinatura"

  @impl true
  def run(_args) do
    Application.put_env(:financeiro, :watch_statements, false)
    Mix.Task.run("app.start")

    case Financeiro.Ledger.LunaClassifier.classify_pending() do
      {:ok, summary} ->
        Mix.shell().info(
          "Luna classificou #{summary.classified} lançamentos em #{summary.batches} lote(s)."
        )

      {:error, reason, summary} ->
        Mix.raise("Luna falhou após classificar #{summary.classified} lançamentos: #{reason}")
    end
  end
end
