defmodule Financeiro.Repo.Migrations.CreateOtherInvestments do
  use Ecto.Migration

  def change do
    create table(:other_investments) do
      add :description, :string, null: false
      add :value_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
