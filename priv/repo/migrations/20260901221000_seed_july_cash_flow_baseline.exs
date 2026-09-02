defmodule Financeiro.Repo.Migrations.SeedJulyCashFlowBaseline do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO cash_flow_months (
      period_start,
      investment_income_expression,
      investment_income_cents,
      capex_expression,
      capex_cents,
      available_cents,
      obligations_cents,
      inserted_at,
      updated_at
    )
    VALUES (
      '2026-07-05',
      '',
      0,
      '',
      0,
      41686255,
      -11658789,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    )
    ON CONFLICT(period_start) DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
