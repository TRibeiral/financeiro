defmodule Financeiro.Repo.Migrations.CreateCashBalances do
  use Ecto.Migration

  def change do
    create table(:cash_balances) do
      add :name, :string, null: false
      add :amount_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
