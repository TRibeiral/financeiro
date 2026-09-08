defmodule Financeiro.Ledger.Classifier do
  @moduledoc "A local, explainable classifier that learns from reviewed merchant history."

  import Ecto.Query
  alias Financeiro.{Repo, Ledger.Transaction}

  @rules [
    {"Mercado",
     ~w(mercado supermercado hortifruti oba carlao pao-minuto pao-de-acucar greenmercado ze-delivery)},
    {"Restaurante",
     ~w(ifd ifood restaurante rest- guaco guapa outback osteria padaria cafe burger pasteis papaya delivery dengo bar-calcada)},
    {"Transporte",
     ~w(uber 99app sem-parar combustivel abastece posto localiza parking park estacionamento nissan)},
    {"Saude",
     ["care plus" | ~w(clinica hospital drogaria farmacia otica olhos defend medica odont vet-)]},
    {"Casa",
     ~w(condominio leroy telhanorte tramontina moveis arquitec revest ar-condici electrolux euroluce refil-design)},
    {"Filho", ~w(brinque brinquedo bebe escola buffet evelibrinque ticco alo-bebe)},
    {"Viagem", ~w(azul booking pousada hotel hoteis linhas-aereas)},
    {"Pet", ~w(finpet petshop pet- veterinaria)},
    {"Funcionarios", ~w(digiane diarista domestica salario funcionaria)},
    {"Extras",
     ~w(netflix spotify youtube audible amazon-prime apple.com google-one anthropic chatgpt ingresso anuidade melimais)}
  ]

  def classify(description, merchant_key \\ nil) do
    key = merchant_key || merchant_key(description)

    case learned_category(key) do
      nil -> rule_category(description)
      category -> {category, 98, "history"}
    end
  end

  def merchant_key(description) do
    description
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.replace(~r/[^a-z0-9 ]/u, " ")
    |> String.replace(
      ~r/\b(transferencia|enviada|recebida|pelo|pix|efetuado|ltda|sa|ct|com|br|parcela|de)\b/u,
      " "
    )
    |> String.replace(~r/\b\d+\b/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp learned_category(""), do: nil

  defp learned_category(key) do
    Repo.one(
      from t in Transaction,
        where: t.merchant_key == ^key and t.review_status == "reviewed",
        order_by: [desc: t.updated_at],
        limit: 1,
        select: t.category
    )
  end

  defp rule_category(description) do
    text = merchant_key(description)

    case Enum.find(@rules, fn {_category, terms} ->
           Enum.any?(terms, &String.contains?(text, &1))
         end) do
      {category, _} -> {category, 82, "rule"}
      nil -> {"Outros", 35, "fallback"}
    end
  end
end
