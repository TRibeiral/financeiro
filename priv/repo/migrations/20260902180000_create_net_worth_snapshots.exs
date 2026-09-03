defmodule Financeiro.Repo.Migrations.CreateNetWorthSnapshots do
  use Ecto.Migration

  def change do
    create table(:net_worth_snapshots) do
      add :captured_at, :utc_datetime, null: false
      add :total_cents, :integer, null: false
      add :cash_cents, :integer, null: false
      add :stocks_cents, :integer, null: false
      add :other_investments_cents, :integer, null: false
      add :cash_count, :integer, null: false, default: 0
      add :stocks_count, :integer, null: false, default: 0
      add :other_investments_count, :integer, null: false, default: 0
      add :stocks_without_quote_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:net_worth_snapshots, [:captured_at])

    create table(:net_worth_snapshot_items) do
      add :snapshot_id,
          references(:net_worth_snapshots, on_delete: :delete_all),
          null: false

      add :category, :string, null: false
      add :name, :string, null: false
      add :value_cents, :integer, null: false
      add :source_id, :integer, null: false
      add :ticker, :string
      add :shares, :integer
      add :quote_cents, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:net_worth_snapshot_items, [:snapshot_id])
    create index(:net_worth_snapshot_items, [:snapshot_id, :category])
  end
end
