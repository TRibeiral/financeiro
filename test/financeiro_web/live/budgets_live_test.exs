defmodule FinanceiroWeb.BudgetsLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Budgets
  alias Financeiro.MonthPeriod

  test "shows monthly and rollover budgets and edits one month independently", %{conn: conn} do
    current_start = MonthPeriod.current_bounds() |> elem(0)

    {:ok, view, html} = live(conn, ~p"/budgets")

    assert html =~ "Orçamentos"
    assert html =~ "Saldo com acúmulo"
    assert html =~ "R$ 55.000,00"
    assert has_element?(view, "#budget-row-#{current_start}")
    assert has_element?(view, "#current-budget-summary")

    view
    |> element("#budget-row-#{current_start} button[phx-click=edit_budget]")
    |> render_click()

    editor = "#budget-editor-#{current_start}"
    changed = view |> form(editor, %{"value" => "60.000,00"}) |> render_change()
    refute changed =~ "Informe um valor igual ou maior que zero"

    html = view |> form(editor, %{"value" => "60.000,00"}) |> render_submit()
    assert html =~ "R$ 60.000,00"
    assert html =~ "personalizado"
    assert Budgets.get_month(current_start).amount_cents == 6_000_000

    view
    |> element("#budget-row-#{current_start} .budget-reset")
    |> render_click()

    assert render(view) =~ "R$ 55.000,00"
    assert is_nil(Budgets.get_month(current_start))
  end

  test "keeps an invalid editor open with an inline error", %{conn: conn} do
    current_start = MonthPeriod.current_bounds() |> elem(0)
    {:ok, view, _html} = live(conn, ~p"/budgets")

    view
    |> element("#budget-row-#{current_start} button[phx-click=edit_budget]")
    |> render_click()

    editor = "#budget-editor-#{current_start}"
    html = view |> form(editor, %{"value" => "-10"}) |> render_submit()

    assert html =~ "Informe um valor igual ou maior que zero"
    assert has_element?(view, editor)
  end
end
