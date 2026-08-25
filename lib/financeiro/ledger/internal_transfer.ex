defmodule Financeiro.Ledger.InternalTransfer do
  @moduledoc "Classifies internal transfers and investment-related movements hidden from spending."

  alias Financeiro.Ledger.Classifier

  @family_names [
    "thiago carneiro ribeiral",
    "ana clara paiva",
    "ana clara de paiva",
    "transf thiago"
  ]

  @account_movements [
    "pagamento recebido",
    "pagamento efetuado",
    "pagamento fatura",
    "fatura paga",
    "resgate rdb"
  ]

  @excluded_movements [
    "credito em conta",
    "rend pago",
    "rendimento",
    "dividendo",
    "dividendos",
    "jscp",
    "juros sobre capital",
    "cor operacoes",
    "cor irrf oper"
  ]

  @refund_movements [
    "estorno",
    "reembolso",
    "devolucao",
    "chargeback"
  ]

  def flow_type(description, amount_cents, source_type) do
    cond do
      excluded?(description) -> "excluded"
      internal?(description, source_type) -> "transfer"
      refund?(description, amount_cents, source_type) -> "refund"
      amount_cents > 0 -> "expense"
      true -> "income"
    end
  end

  def internal?(description, source_type) do
    text = Classifier.merchant_key(description)

    Enum.any?(@family_names, &String.contains?(text, &1)) or
      Enum.any?(@account_movements, &String.contains?(text, &1)) or
      (source_type == "cartão" and String.starts_with?(text, "pagamento"))
  end

  def excluded?(description) do
    text = Classifier.merchant_key(description)
    Enum.any?(@excluded_movements, &String.contains?(text, &1))
  end

  def refund?(description, amount_cents, source_type) do
    text = Classifier.merchant_key(description)

    amount_cents < 0 and
      (source_type == "cartão" or Enum.any?(@refund_movements, &String.contains?(text, &1)))
  end
end
