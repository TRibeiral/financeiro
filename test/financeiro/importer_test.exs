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
    assert InternalTransfer.flow_type("Aplicação RDB", 800_000, "conta") == "excluded"
    assert InternalTransfer.flow_type("Débito em conta", 19_709, "conta") == "excluded"
    assert InternalTransfer.flow_type("SALDO ANTERIOR", -396_793, "conta") == "excluded"

    assert InternalTransfer.flow_type("SALDO TOTAL DISPONÃVEL DIA", -3_327_940, "conta") ==
             "excluded"

    assert InternalTransfer.flow_type("RESGATE CDB DI", -2_400_088, "conta") == "transfer"

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
    04/08/2026,-15.00,old-august,Antes do mês financeiro
    05/08/2026,-25.50,new,Oba Hortifruti
    """)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, import} = Importer.import_file(path, owner: "Teste")
    assert import.inserted_count == 1
    assert import.ignored_count == 2

    [transaction] = Ledger.list_transactions()
    assert transaction.amount_cents == 2550
    assert transaction.category == "Mercado"
    assert transaction.classification_source == "luna"
    assert transaction.classification_confidence == 91
    assert transaction.owner == "Teste"

    assert {:skipped, _} = Importer.import_file(path, owner: "Teste")
    assert Ledger.transaction_count() == 1
  end

  test "uses Ana as the Nubank owner unless an owner is explicitly supplied" do
    default_path =
      Path.join(
        System.tmp_dir!(),
        "financeiro-nubank-default-#{System.unique_integer([:positive])}.csv"
      )

    override_path =
      Path.join(
        System.tmp_dir!(),
        "financeiro-nubank-override-#{System.unique_integer([:positive])}.csv"
      )

    File.write!(default_path, """
    Data,Valor,Identificador,Descrição
    25/08/2026,-10.00,owner-default,Compra padrão
    """)

    File.write!(override_path, """
    Data,Valor,Identificador,Descrição
    25/08/2026,-20.00,owner-override,Compra sobrescrita
    """)

    on_exit(fn ->
      File.rm(default_path)
      File.rm(override_path)
    end)

    assert {:ok, _import} = Importer.import_file(default_path)
    assert {:ok, _import} = Importer.import_file(override_path, owner: "Outra Pessoa")

    owners = Ledger.list_transactions() |> Enum.map(& &1.owner) |> Enum.sort()
    assert owners == ["Ana Clara De Paiva", "Outra Pessoa"]
  end

  test "assigns BREX income to Thiago even when the Nubank file belongs to Ana" do
    path =
      Path.join(
        System.tmp_dir!(),
        "financeiro-brex-owner-#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    Data,Valor,Identificador,Descrição
    14/08/2026,54672.50,brex-income,Transferência Recebida - BREX BRASIL TECNOLOGIA LTDA - 39.315.225/0001-72 - Banco J. P. Morgan S. A. (0376) Agência: 1 Conta: 104301-5
    """)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, _import} = Importer.import_file(path, owner: "Ana Clara De Paiva")
    [income] = Ledger.list_income()
    assert income.owner == "Thiago Carneiro Ribeiral"
  end

  test "stores uploads without overwriting files with the same name" do
    root =
      Path.join(System.tmp_dir!(), "financeiro-storage-#{System.unique_integer([:positive])}")

    directory = Path.join(root, "extratos")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    first_source = Path.join(root, "primeiro.csv")
    second_source = Path.join(root, "segundo.csv")

    File.write!(first_source, """
    Data,Valor,Identificador,Descrição
    25/08/2026,-10.00,storage-1,Primeiro arquivo
    """)

    File.write!(second_source, """
    Data,Valor,Identificador,Descrição
    25/08/2026,-20.00,storage-2,Segundo arquivo
    """)

    assert {:ok, %{path: first_path, storage_status: :stored}} =
             Importer.store_and_import_upload(first_source, "extrato.csv", directory: directory)

    assert {:ok, %{path: second_path, storage_status: :renamed}} =
             Importer.store_and_import_upload(second_source, "extrato.csv", directory: directory)

    assert Path.basename(first_path) == "extrato.csv"
    assert Path.basename(second_path) == "extrato (2).csv"
    assert File.read!(first_path) != File.read!(second_path)
    assert Ledger.transaction_count() == 2
  end
end
