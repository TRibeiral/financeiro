defmodule FinanceiroWeb.StocksLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Investments
  alias Financeiro.Repo

  test "adds owned and watched stocks and filters the portfolio", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/stocks")
    assert html =~ "Sua carteira começa aqui"

    view |> element("button", "Nova ação") |> render_click()

    view
    |> form("#new-stock-form", %{
      "stock" => %{
        "name" => "Petrobras",
        "ticker" => "PETR4",
        "shares" => "100",
        "last_result" => "2T26",
        "tier" => "4",
        "checked_on" => "2026-08-25"
      }
    })
    |> render_submit()

    assert render(view) =~ "Petrobras"
    assert render(view) =~ "100"

    view |> element("button", "Nova ação") |> render_click()

    view
    |> form("#new-stock-form", %{
      "stock" => %{
        "name" => "Vale",
        "ticker" => "VALE3",
        "shares" => "0",
        "last_result" => "1T26",
        "tier" => "2"
      }
    })
    |> render_submit()

    html = view |> element("button[phx-value-view=watched]") |> render_click()
    assert html =~ "Vale"
    refute html =~ "Petrobras"

    html = view |> element("button[phx-value-view=unread]") |> render_click()
    assert html =~ "Vale"
    refute html =~ "Petrobras"
  end

  test "refreshes quotes through the configured Luna provider", %{conn: conn} do
    {:ok, stock} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 5,
        last_result: "2T26"
      })

    {:ok, view, _html} = live(conn, ~p"/stocks")
    view |> element("#refresh-quotes") |> render_click()
    render_async(view, 1_000)

    refreshed = Repo.reload!(stock)
    assert refreshed.quote_cents == 3_750
    assert refreshed.quote_source == "Cotação de teste"
    assert render(view) =~ "R$ 3.750,00"
    assert render(view) =~ "1 cotação atualizada com Luna"
  end

  test "marks purchases pink and restores the tier color on a new quarter", %{conn: conn} do
    {:ok, stock} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 5,
        last_result: "1T26"
      })

    {:ok, view, _html} = live(conn, ~p"/stocks")
    html = view |> element("#stock-#{stock.id} .buy-action") |> render_click()
    assert html =~ "purchased"
    assert Repo.reload!(stock).purchase_heat == 1

    view |> element("#stock-#{stock.id} button[title='Editar ação']") |> render_click()

    view
    |> form("#edit-stock-#{stock.id}", %{
      "stock_id" => stock.id,
      "stock" => %{
        "name" => "Petrobras",
        "ticker" => "PETR4",
        "shares" => "100",
        "last_result" => "2T26",
        "tier" => "5"
      }
    })
    |> render_submit()

    refute render(view) =~ "purchased"
    assert Repo.reload!(stock).purchase_heat == 0
    assert Repo.reload!(stock).tier == 5
  end
end
