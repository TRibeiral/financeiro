defmodule Financeiro.Repo.Migrations.ReclassifyCarePlusReimbursements do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE transactions
    SET flow_type = 'refund',
        category = 'Saude',
        classification_source = 'manual',
        classification_confidence = 100,
        review_status = 'reviewed',
        updated_at = CURRENT_TIMESTAMP
    WHERE amount_cents < 0
      AND source_type = 'conta'
      AND (
        lower(description) LIKE '%care plus%'
        OR description LIKE '%02.725.347/0001-27%'
      )
    """)
  end

  def down do
    :ok
  end
end
