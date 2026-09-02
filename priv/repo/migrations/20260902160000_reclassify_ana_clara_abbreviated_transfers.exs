defmodule Financeiro.Repo.Migrations.ReclassifyAnaClaraAbbreviatedTransfers do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE transactions
    SET flow_type = 'transfer'
    WHERE merchant_key LIKE 'transf ana cla%'
    """)
  end

  def down do
    :ok
  end
end
