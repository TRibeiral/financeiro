defmodule Financeiro.Repo.Migrations.AssignBrexIncomeToThiago do
  use Ecto.Migration

  @owner "Thiago Carneiro Ribeiral"

  def up do
    %{rows: rows} =
      repo().query!("""
      SELECT id, bank, account_ref, source_type, occurred_on, amount_cents,
             merchant_key, source_identifier
      FROM transactions
      WHERE flow_type = 'income'
        AND upper(description) LIKE '%BREX BRASIL TECNOLOGIA LTDA%'
      """)

    Enum.each(rows, fn [
                         id,
                         bank,
                         account_ref,
                         source_type,
                         occurred_on,
                         amount_cents,
                         merchant_key,
                         source_identifier
                       ] ->
      fingerprint =
        fingerprint(%{
          bank: bank,
          owner: @owner,
          account_ref: account_ref,
          source_type: source_type,
          occurred_on: occurred_on,
          amount_cents: amount_cents,
          merchant_key: merchant_key,
          source_identifier: source_identifier
        })

      repo().query!(
        "UPDATE transactions SET owner = ?, fingerprint = ? WHERE id = ?",
        [@owner, fingerprint, id]
      )
    end)
  end

  def down, do: :ok

  defp fingerprint(attrs) do
    identity =
      if attrs.source_identifier not in [nil, ""] do
        [attrs.bank, attrs.owner, attrs.source_type, attrs.source_identifier]
      else
        [
          attrs.bank,
          attrs.owner,
          attrs.account_ref,
          attrs.source_type,
          attrs.occurred_on,
          attrs.amount_cents,
          attrs.merchant_key
        ]
      end

    identity |> Enum.join("|") |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end
end
