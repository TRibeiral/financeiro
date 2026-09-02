defmodule Financeiro.Repo.Migrations.CreateBudgetMonths do
  use Ecto.Migration

  def change do
    create table(:budget_months) do
      add :period_start, :date, null: false
      add :amount_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:budget_months, [:period_start])
  end
end
