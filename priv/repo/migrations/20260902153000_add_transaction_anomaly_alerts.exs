defmodule Financeiro.Repo.Migrations.AddTransactionAnomalyAlerts do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :anomaly_alert, :boolean, null: false, default: false
      add :anomaly_reason, :text
      add :anomaly_confidence, :integer
      add :anomaly_candidate_id, :integer
    end

    create index(:transactions, [:anomaly_alert])
  end
end
