defmodule FinanceiroWeb.SnapshotsLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Cash
  alias Financeiro.Investments
  alias Financeiro.Snapshots

  test "syncs current wealth and reveals the saved positions", %{conn: conn} do
    assert {:ok, _balance} = Cash.create_balance(%{name: "Nubank", amount: "1200,50"})

    assert {:ok, _investment} =
             Investments.create_other_investment(%{
               description: "Tesouro Direto",
               value: "8000,00"
             })

    {:ok, view, html} = live(conn, ~p"/snapshots")

    assert html =~ "Registre o primeiro retrato do patrimônio"
    assert html =~ "R$ 9.200,50"
    assert has_element?(view, "#sync-snapshot")

    view |> element("#sync-snapshot") |> render_click()

    assert has_element?(view, "#latest-net-worth", "R$ 9.200,50")
    assert render(view) =~ "Snapshot do patrimônio salvo"
    assert render(view) =~ "Evolução do patrimônio"

    [snapshot] = Snapshots.list_snapshots()
    assert has_element?(view, "#snapshot-#{snapshot.id}")

    view
    |> element("#snapshot-#{snapshot.id} .snapshot-row-summary")
    |> render_click()

    html = render(view)
    assert html =~ "Nubank"
    assert html =~ "Tesouro Direto"
    assert html =~ "Nenhuma posição registrada"
  end

  test "warns when an owned stock has no quote", %{conn: conn} do
    assert {:ok, _stock} =
             Investments.create_stock(%{
               name: "Cotação pendente",
               ticker: "COTE3",
               shares: 10,
               last_result: "2T26",
               tier: 1
             })

    {:ok, view, html} = live(conn, ~p"/snapshots")

    assert html =~ "ação está"
    assert html =~ "sem cotação"
    assert has_element?(view, ".snapshot-warning a[href='/stocks']")
  end
end
