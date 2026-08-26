defmodule FinanceiroWeb.ImportsLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Ledger

  test "asks for the Nubank owner before importing a dropped statement", %{conn: conn} do
    directory =
      Path.join(
        System.tmp_dir!(),
        "financeiro-upload-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    previous_directory = Application.fetch_env!(:financeiro, :statements_dir)
    Application.put_env(:financeiro, :statements_dir, directory)

    on_exit(fn ->
      Application.put_env(:financeiro, :statements_dir, previous_directory)
      File.rm_rf!(directory)
    end)

    content = """
    Data,Valor,Identificador,Descrição
    25/08/2026,-25.50,upload-1,Oba Hortifruti
    """

    {:ok, view, html} = live(conn, ~p"/imports")
    assert html =~ directory
    assert has_element?(view, "input[type=file][name=statements]")

    upload =
      file_input(view, "#statement-upload", :statements, [
        %{
          name: "novo-extrato.csv",
          content: content,
          type: "text/csv"
        }
      ])

    html = render_upload(upload, "novo-extrato.csv")

    refute File.exists?(Path.join(directory, "novo-extrato.csv"))
    assert html =~ "Este arquivo Nubank é de quem?"
    assert html =~ "Ana"
    assert html =~ "Thiago"

    html =
      view
      |> element("button[phx-click='confirm-nubank-owner'][phx-value-owner='ana']")
      |> render_click()

    assert File.read!(Path.join(directory, "novo-extrato.csv")) == content
    assert html =~ "movido para a pasta de extratos"
    assert html =~ "1 novos lançamentos"
    assert Ledger.transaction_count() == 1
    assert hd(Ledger.list_transactions()).owner == "Ana Clara De Paiva"
  end
end
