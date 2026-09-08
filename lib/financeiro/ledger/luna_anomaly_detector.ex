defmodule Financeiro.Ledger.LunaAnomalyDetector do
  @moduledoc "Checks newly imported card expenses for changed-snapshot anomalies with a separate Luna run."

  import Ecto.Query

  alias Financeiro.Repo
  alias Financeiro.Ledger.Transaction

  @date_window 5

  def inspect_import(ids, opts \\ []) do
    transactions =
      Repo.all(
        from t in Transaction,
          where:
            t.id in ^ids and t.flow_type in ["expense", "refund"] and
              t.source_type == "cartão" and
              (is_nil(t.source_identifier) or t.source_identifier == "") and
              is_nil(t.anomaly_resolution),
          order_by: t.id
      )

    cases =
      transactions
      |> Enum.map(&build_case/1)
      |> Enum.reject(&(&1.candidates == []))

    if cases == [] do
      {:ok, %{inspected: length(transactions), flagged: 0}}
    else
      cases
      |> Enum.chunk_every(5)
      |> Enum.reduce_while(
        {:ok, %{inspected: length(transactions), flagged: 0, batches: 0}},
        fn batch, {:ok, summary} ->
          case run(batch, opts) do
            {:ok, flagged} ->
              {:cont,
               {:ok,
                %{summary | flagged: summary.flagged + flagged, batches: summary.batches + 1}}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )
    end
  end

  def inspect_history(opts \\ []) do
    ids =
      Repo.all(
        from t in Transaction,
          where: t.flow_type in ["expense", "refund"],
          order_by: [asc: t.inserted_at, asc: t.id],
          select: t.id
      )

    inspect_import(ids, opts)
  end

  defp build_case(transaction) do
    from_date = Date.add(transaction.occurred_on, -@date_window)
    to_date = Date.add(transaction.occurred_on, @date_window)

    candidates =
      Repo.all(
        from t in Transaction,
          where:
            t.id != ^transaction.id and t.inserted_at < ^transaction.inserted_at and
              t.bank == ^transaction.bank and
              t.owner == ^transaction.owner and t.source_type == ^transaction.source_type and
              t.merchant_key == ^transaction.merchant_key and
              is_nil(t.anomaly_resolution) and
              t.flow_type in ["expense", "refund"] and t.occurred_on >= ^from_date and
              t.occurred_on <= ^to_date,
          order_by: [desc: t.occurred_on, desc: t.id],
          limit: 40,
          select: %{
            id: t.id,
            date: t.occurred_on,
            amount_cents: t.amount_cents,
            description: t.description,
            merchant_key: t.merchant_key
          }
      )

    %{transaction: payload(transaction), candidates: candidates}
  end

  defp payload(transaction) do
    %{
      id: transaction.id,
      date: transaction.occurred_on,
      amount_cents: transaction.amount_cents,
      description: transaction.description,
      merchant_key: transaction.merchant_key,
      bank: transaction.bank,
      owner: transaction.owner,
      source_type: transaction.source_type
    }
  end

  defp run(cases, opts) do
    runner =
      Keyword.get(
        opts,
        :runner,
        Application.get_env(:financeiro, :codex_runner, Financeiro.CodexRunner)
      )

    runner_opts =
      opts
      |> Keyword.put(
        :output_schema,
        Application.app_dir(:financeiro, "priv/luna_anomaly.schema.json")
      )
      |> Keyword.put(:output_key, "alerts")

    with {:ok, results} <- runner.run(prompt(cases), runner_opts),
         {:ok, alerts} <- validate(results, cases),
         :ok <- persist(alerts) do
      {:ok, Enum.count(alerts, & &1.flagged)}
    end
  end

  defp prompt(cases) do
    """
    Analise possíveis anomalias de importação em lançamentos de cartão. Esta tarefa é somente
    para detectar se um lançamento novo pode ser uma versão alterada de um lançamento anterior.
    Não classifique categorias.

    Regras:
    - Compare cada transaction somente com seus candidates.
    - Marque possible_changed_transaction=true quando a descrição/estabelecimento indicar a mesma
      compra, mas data e/ou valor mudaram entre exportações do banco.
    - Compras recorrentes ou múltiplas compras legítimas no mesmo estabelecimento não são versões.
    - Intermediadores e estabelecimentos de uso frequente, como Ifd*/iFood, Uber, Apple e mercados,
      repetem descrições naturalmente. Nunca sinalize esses casos somente por descrição semelhante,
      proximidade de datas ou diferença de valor; exija evidência adicional inequívoca.
    - Na dúvida, marque false. Prefira precisão a quantidade de alertas.
    - candidate_id deve identificar o candidato mais provável quando true, e ser null quando false.
    - confidence é de 0 a 100 e reason deve explicar brevemente os sinais encontrados.
    - Responda uma vez para cada transaction id, sem omitir ou inventar ids.
    - Não use ferramentas, arquivos ou comandos.

    Casos:
    #{Jason.encode!(cases)}
    """
  end

  defp validate(results, cases) do
    expected = cases |> Enum.map(& &1.transaction.id) |> MapSet.new()

    candidate_ids =
      Map.new(cases, fn item ->
        {item.transaction.id, item.candidates |> Enum.map(& &1.id) |> MapSet.new()}
      end)

    normalized =
      Enum.reduce_while(results, [], fn result, acc ->
        id = result["id"] || result[:id]
        flagged = result["possible_changed_transaction"]
        candidate_id = result["candidate_id"]
        confidence = result["confidence"]
        reason = result["reason"]

        valid_candidate =
          (flagged == false and is_nil(candidate_id)) or
            (flagged == true and
               MapSet.member?(Map.get(candidate_ids, id, MapSet.new()), candidate_id))

        if is_integer(id) and MapSet.member?(expected, id) and is_boolean(flagged) and
             is_integer(confidence) and confidence in 0..100 and is_binary(reason) and
             valid_candidate do
          {:cont,
           [
             %{
               id: id,
               flagged: flagged,
               candidate_id: candidate_id,
               confidence: confidence,
               reason: reason
             }
             | acc
           ]}
        else
          {:halt, :invalid}
        end
      end)

    ids = if is_list(normalized), do: MapSet.new(normalized, & &1.id), else: MapSet.new()

    if is_list(normalized) and ids == expected and length(normalized) == MapSet.size(expected),
      do: {:ok, normalized},
      else: {:error, "Luna retornou uma análise de anomalias inválida"}
  end

  defp persist(alerts) do
    Repo.transaction(fn ->
      Enum.each(alerts, fn alert ->
        from(t in Transaction,
          where: t.id == ^alert.id and is_nil(t.anomaly_resolution)
        )
        |> Repo.update_all(
          set: [
            anomaly_alert: alert.flagged,
            anomaly_candidate_id: alert.candidate_id,
            anomaly_confidence: alert.confidence,
            anomaly_reason: alert.reason,
            updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
          ]
        )

        if alert.flagged do
          from(t in Transaction,
            where: t.id == ^alert.candidate_id and is_nil(t.anomaly_resolution)
          )
          |> Repo.update_all(
            set: [
              anomaly_alert: true,
              anomaly_candidate_id: alert.id,
              anomaly_confidence: alert.confidence,
              anomaly_reason: "Par relacionado: #{alert.reason}",
              updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
            ]
          )
        end
      end)
    end)

    :ok
  end
end
