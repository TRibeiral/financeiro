defmodule Financeiro.Repo.Migrations.AddTransactionUndoState do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      add :previous_category, :string
      add :previous_review_status, :string
      add :previous_classification_source, :string
      add :previous_classification_confidence, :integer
      add :undo_action_id, :string
    end

    create index(:transactions, [:undo_action_id])
  end
end
