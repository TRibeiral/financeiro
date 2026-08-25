defmodule Financeiro.Repo.Migrations.ReclassifyBalanceAndCdbMovements do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE transactions
    SET flow_type = 'excluded'
    WHERE merchant_key IN ('saldo anterior', 'saldo total disponavel dia')
    """)

    execute("""
    UPDATE transactions
    SET flow_type = 'transfer'
    WHERE merchant_key LIKE 'resgate cdb%'
    """)
  end

  def down do
    :ok
  end
end
