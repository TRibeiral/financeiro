defmodule Financeiro.Ledger.LunaClassifier do
  @moduledoc "Classifies unresolved transactions with GPT-5.6 Luna through the local Codex CLI."

  import Ecto.Query
  require Logger

  alias Financeiro.Repo
  alias Financeiro.Ledger.Transaction

  @categories Transaction.categories()
  @unresolved_sources ~w(rule fallback automatic luna_error)

  def classify_pending(opts \\ []) do
    ids = Keyword.get(opts, :ids)
    batch_size = Keyword.get(opts, :batch_size, 5)

    transactions =
      from(t in Transaction,
        where:
          t.review_status == "pending" and t.flow_type in ["expense", "refund"] and
            t.classification_source in ^@unresolved_sources,
        order_by: [asc: t.id]
      )
      |> maybe_filter_ids(ids)
      |> Repo.all()

    transactions
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce_while({:ok, %{classified: 0, batches: 0}}, fn batch, {:ok, summary} ->
      case classify_batch(batch, opts) do
        {:ok, count} ->
          {:cont, {:ok, %{classified: summary.classified + count, batches: summary.batches + 1}}}

        {:error, reason} ->
          mark_failed(batch)
          {:halt, {:error, reason, summary}}
      end
    end)
  end

  def pending_luna_count do
    Repo.aggregate(
      from(t in Transaction,
        where:
          t.review_status == "pending" and t.flow_type in ["expense", "refund"] and
            t.classification_source in ^@unresolved_sources
      ),
      :count
    )
  end

  defp classify_batch(transactions, opts) do
    runner =
      Keyword.get(
        opts,
        :runner,
        Application.get_env(:financeiro, :codex_runner, Financeiro.CodexRunner)
      )

    prompt = prompt(transactions)

    with {:ok, results} <- runner.run(prompt, opts),
         {:ok, normalized} <- validate_results(results, transactions) do
      persist(normalized)
    end
  end

  defp prompt(transactions) do
    history = reviewed_history()

    payload =
      Enum.map(transactions, fn transaction ->
        %{
          id: transaction.id,
          date: Date.to_iso8601(transaction.occurred_on),
          amount_cents: transaction.amount_cents,
          description: transaction.description,
          merchant_key: transaction.merchant_key,
          bank: transaction.bank,
          owner: transaction.owner,
          flow_type: transaction.flow_type,
          preliminary_category: transaction.category
        }
      end)

    """
    Classifique os lançamentos financeiros pessoais abaixo. Responda somente no formato do JSON Schema fornecido.

    Regras obrigatórias:
    - Use exatamente uma destas categorias: #{Enum.join(@categories, ", ")}.
    - Classifique cada id exatamente uma vez, sem omitir ou inventar ids.
    - Use o histórico manual como principal referência para estabelecimentos semelhantes.
    - A categoria preliminar é apenas uma pista; corrija-a quando necessário.
    - Estornos e reembolsos devem receber a categoria da compra original que estão abatendo.
    - Descrições sem uma natureza de gasto clara devem ficar em Outros.
    - confidence deve ser um inteiro de 0 a 100.
    - Não use ferramentas, não leia arquivos e não execute comandos. Esta é apenas uma tarefa de classificação.

    Histórico manual revisado:
    #{Jason.encode!(history)}

    Lançamentos:
    #{Jason.encode!(payload)}
    """
  end

  defp reviewed_history do
    from(t in Transaction,
      where: t.review_status == "reviewed",
      order_by: [desc: t.updated_at],
      limit: 150,
      select: %{merchant_key: t.merchant_key, description: t.description, category: t.category}
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.merchant_key)
  end

  defp validate_results(results, transactions) do
    expected_ids = transactions |> Enum.map(& &1.id) |> MapSet.new()

    normalized =
      Enum.reduce_while(results, [], fn result, acc ->
        id = result["id"] || result[:id]
        category = result["category"] || result[:category]
        confidence = result["confidence"] || result[:confidence]

        if is_integer(id) and MapSet.member?(expected_ids, id) and category in @categories and
             is_integer(confidence) and confidence in 0..100 do
          {:cont, [%{id: id, category: category, confidence: confidence} | acc]}
        else
          {:halt, :invalid}
        end
      end)

    received_ids =
      if is_list(normalized),
        do: normalized |> Enum.map(& &1.id) |> MapSet.new(),
        else: MapSet.new()

    if is_list(normalized) and length(normalized) == MapSet.size(expected_ids) and
         received_ids == expected_ids do
      {:ok, normalized}
    else
      {:error, "Luna retornou ids, categorias ou níveis de confiança inválidos"}
    end
  end

  defp persist(classifications) do
    Repo.transaction(fn ->
      Enum.each(classifications, fn %{id: id, category: category, confidence: confidence} ->
        from(t in Transaction, where: t.id == ^id and t.review_status == "pending")
        |> Repo.update_all(
          set: [
            category: category,
            classification_source: "luna",
            classification_confidence: confidence,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )
      end)
    end)

    {:ok, length(classifications)}
  end

  defp mark_failed(transactions) do
    ids = Enum.map(transactions, & &1.id)

    from(t in Transaction,
      where: t.id in ^ids and t.review_status == "pending"
    )
    |> Repo.update_all(
      set: [
        classification_source: "luna_error",
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )

    Logger.error("A classificação pelo Codex Luna falhou para #{length(ids)} lançamentos")
  end

  defp maybe_filter_ids(query, nil), do: query
  defp maybe_filter_ids(query, ids), do: where(query, [t], t.id in ^ids)
end
