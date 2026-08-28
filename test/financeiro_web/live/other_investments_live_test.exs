defmodule FinanceiroWeb.OtherInvestmentsLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Investments

  test "adds, edits, and removes other investments", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/other-investments")

    assert html =~ "Adicione seu primeiro investimento"
    assert html =~ "R$ 0,00"

    view
    |> form("#new-other-investment-form", %{
      "investment" => %{"description" => "Tesouro Direto", "value" => "12500,50"}
    })
    |> render_submit()

    view
    |> form("#new-other-investment-form", %{
      "investment" => %{"description" => "Fundo imobiliário", "value" => "3500"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Tesouro Direto"
    assert html =~ "Fundo imobiliário"
    assert html =~ "R$ 16.000,50"

    [treasury, fund] = Investments.list_other_investments()

    view
    |> element("#other-investment-#{treasury.id} button[phx-click=edit]")
    |> render_click()

    view
    |> form("#edit-other-investment-#{treasury.id}", %{
      "investment" => %{"description" => "Tesouro Selic", "value" => "14000"}
    })
    |> render_submit()

    assert render(view) =~ "Tesouro Selic"
    assert render(view) =~ "R$ 17.500,00"

    view
    |> element("#other-investment-#{fund.id} button[phx-click=delete]")
    |> render_click()

    refute has_element?(view, "#other-investment-#{fund.id}")
    assert render(view) =~ "R$ 14.000,00"
  end

  test "does not accept negative values", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/other-investments")

    html =
      view
      |> form("#new-other-investment-form", %{
        "investment" => %{"description" => "Inválido", "value" => "-1"}
      })
      |> render_submit()

    assert html =~ "deve ser maior que zero"
    assert Investments.list_other_investments() == []
  end
end
