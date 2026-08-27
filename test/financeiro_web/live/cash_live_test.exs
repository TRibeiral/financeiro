defmodule FinanceiroWeb.CashLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Cash

  test "adds, edits, and removes positive and negative cash rows", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/cash")

    assert html =~ "Seu caixa começa aqui"
    assert html =~ "R$ 0,00"

    view
    |> form("#new-balance-form", %{"balance" => %{"name" => "Nubank", "amount" => "2500.50"}})
    |> render_submit()

    view
    |> form("#new-balance-form", %{
      "balance" => %{"name" => "Cartão Itaú", "amount" => "-700,25"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Nubank"
    assert html =~ "Cartão Itaú"
    assert html =~ "R$ 2.500,50"
    assert html =~ "−R$ 700,25"
    assert html =~ "R$ 1.800,25"

    [account, card] = Cash.list_balances()

    view |> element("#balance-#{account.id} button[phx-click=edit]") |> render_click()

    view
    |> form("#edit-balance-#{account.id}", %{
      "balance" => %{"name" => "Conta principal", "amount" => "3000"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Conta principal"
    assert html =~ "R$ 2.299,75"

    view |> element("#balance-#{card.id} button[phx-click=delete]") |> render_click()
    refute has_element?(view, "#balance-#{card.id}")
    assert render(view) =~ "R$ 3.000,00"
  end

  test "shows amount validation feedback", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cash")

    html =
      view
      |> form("#new-balance-form", %{"balance" => %{"name" => "Conta", "amount" => "abc"}})
      |> render_submit()

    assert html =~ "use um valor como 1250,00 ou -450,90"
  end
end
