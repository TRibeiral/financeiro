defmodule FinanceiroWeb.CashFlowLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Cash
  alias Financeiro.Ledger.Transaction
  alias Financeiro.MonthPeriod
  alias Financeiro.Repo

  test "saves summed inputs and snapshots both sides of the current Caixa", %{conn: conn} do
    current_start = MonthPeriod.current_bounds() |> elem(0)
    transaction_fixture(current_start, "income", -100_000)
    transaction_fixture(current_start, "expense", 25_000)

    {:ok, _account} = Cash.create_balance(%{name: "Conta", amount: "420000"})
    {:ok, _card} = Cash.create_balance(%{name: "Cartão", amount: "-100000"})

    {:ok, view, html} = live(conn, ~p"/cash-flow")
    assert html =~ "Visão mensal"
    assert html =~ "Panorama financeiro · ciclos do dia 5 ao dia 4"
    assert html =~ "R$ 1.000,00"
    assert html =~ "R$ 250,00"

    assert html =~ "EBIDA"
    assert html =~ "R$ 416.862,55"
    assert html =~ "−R$ 116.587,89"
    assert html =~ "R$ 300.274,66"

    income_editor = "#cell-editor-investment_income-#{current_start}"
    capex_editor = "#cell-editor-capex-#{current_start}"

    view
    |> element("#cash-flow-row-#{current_start} button[phx-value-field=investment_income]")
    |> render_click()

    preview = view |> form(income_editor, %{"value" => "2+440+59"}) |> render_change()

    assert preview =~ "R$ 501,00"

    view |> form(income_editor, %{"value" => "2+440+59"}) |> render_submit()

    view
    |> element("#cash-flow-row-#{current_start} button[phx-value-field=capex]")
    |> render_click()

    preview = view |> form(capex_editor, %{"value" => "100+25"}) |> render_change()
    assert preview =~ "R$ 125,00"

    view |> form(capex_editor, %{"value" => "100+25"}) |> render_submit()

    view |> element("#sync-cash") |> render_click()

    html = render(view)
    assert html =~ "R$ 420.000,00"
    assert html =~ "−R$ 100.000,00"
    assert html =~ "R$ 320.000,00"
    assert has_element?(view, "#current-free-cash-flow", "R$ 19.349,34")
  end

  defp transaction_fixture(date, flow_type, amount_cents) do
    unique = System.unique_integer([:positive])

    %Transaction{}
    |> Transaction.changeset(%{
      occurred_on: date,
      amount_cents: amount_cents,
      description: "Movimento #{unique}",
      merchant_key: "movimento #{unique}",
      flow_type: flow_type,
      category: "Outros",
      review_status: "reviewed",
      bank: "Teste",
      owner: "Thiago",
      source_type: "conta",
      source_file: "teste.csv",
      fingerprint: "cash-flow-live-#{unique}"
    })
    |> Repo.insert!()
  end
end
