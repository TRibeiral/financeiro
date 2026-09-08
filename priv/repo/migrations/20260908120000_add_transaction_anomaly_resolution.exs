defmodule Financeiro.Repo.Migrations.AddTransactionAnomalyResolution do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :anomaly_resolution, :string
    end

    create index(:transactions, [:anomaly_resolution])
  end
end
