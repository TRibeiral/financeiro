defmodule Financeiro.Repo.Migrations.CreateFinanceTables do
  use Ecto.Migration

  def change do
    create table(:imports) do
      add :filename, :string, null: false
      add :path, :string, null: false
      add :file_hash, :string, null: false
      add :bank, :string
      add :owner, :string
      add :status, :string, null: false, default: "completed"
      add :inserted_count, :integer, null: false, default: 0
      add :duplicate_count, :integer, null: false, default: 0
      add :ignored_count, :integer, null: false, default: 0
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:imports, [:file_hash])
    create index(:imports, [:inserted_at])

    create table(:transactions) do
      add :occurred_on, :date, null: false
      add :amount_cents, :integer, null: false
      add :description, :text, null: false
      add :merchant_key, :string, null: false
      add :flow_type, :string, null: false, default: "expense"
      add :category, :string, null: false, default: "Outros"
      add :classification_source, :string, null: false, default: "automatic"
      add :classification_confidence, :integer, null: false, default: 0
      add :review_status, :string, null: false, default: "pending"
      add :bank, :string, null: false
      add :owner, :string, null: false
      add :account_ref, :string
      add :source_type, :string, null: false
      add :source_file, :string, null: false
      add :source_identifier, :string
      add :fingerprint, :string, null: false
      add :raw_data, :map, null: false, default: %{}
      add :import_id, references(:imports, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:transactions, [:fingerprint])
    create index(:transactions, [:occurred_on])
    create index(:transactions, [:category])
    create index(:transactions, [:review_status])
    create index(:transactions, [:owner])
    create index(:transactions, [:bank])
    create index(:transactions, [:merchant_key])
    create index(:transactions, [:flow_type])
  end
end
