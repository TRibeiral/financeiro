defmodule Financeiro.Repo.Migrations.ExcludeRdbApplicationsAndAccountDebits do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE transactions
    SET flow_type = 'excluded'
    WHERE merchant_key IN ('aplicacao rdb', 'debito em conta')
    """)
  end

  def down do
    :ok
  end
end
