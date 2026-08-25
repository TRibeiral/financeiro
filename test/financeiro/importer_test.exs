defmodule Financeiro.ImporterTest do
  use Financeiro.DataCase

  alias Financeiro.{Importer, Ledger}
  alias Financeiro.Ledger.Classifier
  alias Financeiro.Ledger.InternalTransfer

  test "normalizes merchant names without accents or account noise" do
    assert Classifier.merchant_key("Transferência enviada pelo Pix - Oba Hortifruti 123") ==
             "oba hortifruti"
  end

  test "excludes movements between Thiago and Ana and between own accounts" do
    assert InternalTransfer.flow_type(
             "Transferência enviada pelo Pix - Ana Clara de Paiva Cardoso",
             100_000,
             "conta"
           ) == "transfer"

    assert InternalTransfer.flow_type(
             "Transferência recebida - Ana Clara de Paiva Cardoso",
             -100_000,
             "conta"
           ) == "transfer"

    assert InternalTransfer.flow_type("PIX TRANSF Thiago 18/08", -450_000, "conta") ==
             "transfer"

    assert InternalTransfer.flow_type("Pagamento de fatura", 128_837, "conta") == "transfer"
    assert InternalTransfer.flow_type("REND PAGO APLIC AUT MAIS", -22, "conta") == "excluded"
    assert InternalTransfer.flow_type("COR IRRF OPER. B3 17/08", 168, "conta") == "excluded"
    assert InternalTransfer.flow_type("COR JSCP PETR4", -14_458, "conta") == "excluded"
    assert InternalTransfer.flow_type("Crédito em conta", -4_008, "conta") == "excluded"

    assert InternalTransfer.flow_type(
             "Transferência Recebida - BREX BRASIL TECNOLOGIA LTDA",
             -5_467_250,
             "conta"
           ) == "income"

    assert InternalTransfer.flow_type("Estorno De Anuidade Dif", -10_500, "cartão") == "refund"
    assert InternalTransfer.flow_type("Oba Hortifruti", 2_550, "conta") == "expense"
  end

  test "imports a Nubank account CSV after the boundary and skips the same file twice" do
    path =
      Path.join(System.tmp_dir!(), "financeiro-import-#{System.unique_integer([:positive])}.csv")

    File.write!(path, """
    Data,Valor,Identificador,Descrição
    31/07/2026,-10.00,old,Antes do início
    01/08/2026,-25.50,new,Oba Hortifruti
    """)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, import} = Importer.import_file(path, owner: "Teste")
    assert import.inserted_count == 1
    assert import.ignored_count == 1

    [transaction] = Ledger.list_transactions()
    assert transaction.amount_cents == 2550
    assert transaction.category == "Mercado"
    assert transaction.classification_source == "luna"
    assert transaction.classification_confidence == 91
    assert transaction.owner == "Teste"

    assert {:skipped, _} = Importer.import_file(path, owner: "Teste")
    assert Ledger.transaction_count() == 1
  end
end
