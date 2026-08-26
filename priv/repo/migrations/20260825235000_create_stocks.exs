defmodule Financeiro.Repo.Migrations.CreateStocks do
  use Ecto.Migration

  def change do
    create table(:stocks) do
      add :name, :string, null: false
      add :ticker, :string, null: false
      add :shares, :integer, null: false, default: 0
      add :quote_cents, :integer
      add :last_result, :string, null: false, default: "2T26"
      add :tier, :integer, null: false, default: 0
      add :checked_on, :date
      add :purchase_heat, :integer, null: false, default: 0
      add :quote_refreshed_at, :utc_datetime
      add :quote_source, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:stocks, [:ticker])
    create index(:stocks, [:shares])
    create index(:stocks, [:tier])
    create index(:stocks, [:last_result])
  end
end
