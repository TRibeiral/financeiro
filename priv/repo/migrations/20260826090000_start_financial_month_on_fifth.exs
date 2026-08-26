defmodule Financeiro.Repo.Migrations.StartFinancialMonthOnFifth do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE imports
    SET ignored_count = ignored_count + (
          SELECT count(*) FROM transactions
          WHERE transactions.import_id = imports.id
            AND transactions.occurred_on < '2026-08-05'
        ),
        inserted_count = inserted_count - (
          SELECT count(*) FROM transactions
          WHERE transactions.import_id = imports.id
            AND transactions.occurred_on < '2026-08-05'
        )
    WHERE EXISTS (
      SELECT 1 FROM transactions
      WHERE transactions.import_id = imports.id
        AND transactions.occurred_on < '2026-08-05'
    )
    """)

    execute("DELETE FROM transactions WHERE occurred_on < '2026-08-05'")
  end

  def down, do: :ok
end
