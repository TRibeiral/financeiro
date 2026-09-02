defmodule Financeiro.Repo.Migrations.CreateCashFlowMonths do
  use Ecto.Migration

  def change do
    create table(:cash_flow_months) do
      add :period_start, :date, null: false
      add :investment_income_expression, :string, null: false, default: ""
      add :investment_income_cents, :integer, null: false, default: 0
      add :capex_expression, :string, null: false, default: ""
      add :capex_cents, :integer, null: false, default: 0
      add :available_cents, :integer
      add :obligations_cents, :integer
      add :cash_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cash_flow_months, [:period_start])
  end
end
