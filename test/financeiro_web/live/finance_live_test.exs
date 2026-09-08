defmodule FinanceiroWeb.FinanceLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Ledger
  alias Financeiro.Repo
  alias Financeiro.Ledger.Transaction

  test "lists and confirms a transaction", %{conn: conn} do
    transaction = transaction_fixture()
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Oba Hortifruti"
    assert html =~ "R$ 25,50"
    assert html =~ "Nubank · cartão"

    view
    |> element("button[phx-click=review][phx-value-id='#{transaction.id}']")
    |> render_click()

    assert Repo.reload!(transaction).review_status == "reviewed"
  end

  test "shows Luna's anomaly alert on a suspicious expense", %{conn: conn} do
    transaction_fixture(%{
      anomaly_alert: true,
      anomaly_confidence: 92,
      anomaly_reason: "Data e valor mudaram entre exportações",
      anomaly_candidate_id: 123
    })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             "[title*='Possível lançamento alterado (92%)'] .anomaly-alert-icon"
           )
  end

  test "offers and persists the Projetos category", %{conn: conn} do
    transaction = transaction_fixture()
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "form.category-form option[value=Projetos]", "Projetos")

    view
    |> form("form.category-form", %{
      "transaction_id" => to_string(transaction.id),
      "category" => "Projetos"
    })
    |> render_change()

    saved = Repo.reload!(transaction)
    assert saved.category == "Projetos"
    assert saved.review_status == "pending"
  end

  test "saves a category without confirming and can confirm again after undo", %{conn: conn} do
    transaction = transaction_fixture()
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form.category-form", %{
        "transaction_id" => to_string(transaction.id),
        "category" => "Casa"
      })
      |> render_change()

    changed = Repo.reload!(transaction)
    assert changed.category == "Casa"
    assert changed.review_status == "pending"
    assert changed.classification_source == "manual"
    assert changed.undo_action_id
    assert html =~ "salva no banco de dados"
    assert html =~ "salvo · falta confirmar"

    view
    |> element("button[phx-click=review][phx-value-id='#{transaction.id}']")
    |> render_click()

    confirmed = Repo.reload!(transaction)
    assert confirmed.category == "Casa"
    assert confirmed.review_status == "reviewed"

    view
    |> element("button[phx-click=undo_or_reopen][phx-value-id='#{transaction.id}']")
    |> render_click()

    restored = Repo.reload!(transaction)
    assert restored.category == "Casa"
    assert restored.review_status == "pending"
    assert restored.classification_source == "manual"
    assert restored.classification_confidence == 100
    refute restored.undo_action_id

    view
    |> element("button[phx-click=review][phx-value-id='#{transaction.id}']")
    |> render_click()

    assert Repo.reload!(transaction).review_status == "reviewed"
  end

  test "changes an already confirmed category in the database and can undo it", %{conn: conn} do
    transaction =
      transaction_fixture(%{
        review_status: "reviewed",
        classification_source: "manual",
        classification_confidence: 100
      })

    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view
      |> form("form.category-form", %{
        "transaction_id" => to_string(transaction.id),
        "category" => "Casa"
      })
      |> render_change()

    saved = Repo.reload!(transaction)
    assert saved.category == "Casa"
    assert saved.review_status == "reviewed"
    assert saved.classification_source == "manual"
    assert html =~ "salva no banco de dados"
    assert html =~ "salvo no banco"

    view
    |> element("button[phx-click=undo_or_reopen][phx-value-id='#{transaction.id}']")
    |> render_click()

    restored = Repo.reload!(transaction)
    assert restored.category == "Mercado"
    assert restored.review_status == "reviewed"
  end

  test "reopens legacy confirmed transactions and confirms them again", %{conn: conn} do
    transaction =
      transaction_fixture(%{
        review_status: "reviewed",
        classification_source: "manual",
        classification_confidence: 100
      })

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> element("button[phx-click=undo_or_reopen][phx-value-id='#{transaction.id}']")
    |> render_click()

    reopened = Repo.reload!(transaction)
    assert reopened.category == "Mercado"
    assert reopened.review_status == "pending"

    view
    |> element("button[phx-click=review][phx-value-id='#{transaction.id}']")
    |> render_click()

    assert Repo.reload!(transaction).review_status == "reviewed"
  end

  test "review queue changes category and confirms", %{conn: conn} do
    transaction_fixture()
    {:ok, view, html} = live(conn, ~p"/review")
    assert html =~ "Oba Hortifruti"

    view |> element("button[phx-value-category=Casa]") |> render_click()
    view |> element("button[phx-click=approve]") |> render_click()

    assert render(view) =~ "Tudo revisado"
  end

  test "undoes confirm-similar as one grouped action", %{conn: conn} do
    first = transaction_fixture()
    second = transaction_fixture(%{fingerprint: "similar-#{System.unique_integer([:positive])}"})

    {:ok, view, _html} = live(conn, ~p"/review")
    view |> element("button[phx-value-category=Casa]") |> render_click()
    view |> element("button[phx-click=approve_similar]") |> render_click()

    assert Repo.reload!(first).category == "Casa"
    assert Repo.reload!(second).review_status == "reviewed"

    view |> element("button[phx-click=undo]") |> render_click()

    assert Repo.reload!(first).category == "Mercado"
    assert Repo.reload!(first).review_status == "pending"
    assert Repo.reload!(second).category == "Mercado"
    assert Repo.reload!(second).review_status == "pending"
  end

  test "never exposes transfers, income, credits or B3 on expenses or its totals", %{conn: conn} do
    transaction_fixture()

    transaction_fixture(%{
      description: "PIX TRANSF Thiago",
      merchant_key: "transf thiago",
      flow_type: "transfer",
      amount_cents: 300_000,
      bank: "Itaú"
    })

    transaction_fixture(%{
      description: "COR JSCP PETR4",
      merchant_key: "cor jscp petr",
      flow_type: "excluded",
      amount_cents: -14_458,
      bank: "Itaú",
      source_type: "conta"
    })

    transaction_fixture(%{
      description: "Salário recebido",
      merchant_key: "salario recebido",
      flow_type: "income",
      amount_cents: -500_000,
      source_type: "conta"
    })

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Oba Hortifruti"
    assert html =~ "R$ 25,50"
    refute html =~ "PIX TRANSF Thiago"
    refute html =~ "COR JSCP PETR4"
    refute html =~ "Salário recebido"
    refute has_element?(view, "option[value=transfers]")
    refute has_element?(view, "option[value=excluded]")
    refute has_element?(view, "option[value=transfer]")

    for forbidden <- ~w(transfers excluded credits) do
      forged_html = render_change(view, "filter", %{"filters" => %{"direction" => forbidden}})
      refute forged_html =~ "PIX TRANSF Thiago"
      refute forged_html =~ "COR JSCP PETR4"
      refute forged_html =~ "Salário recebido"
    end

    assert Ledger.totals() == %{expenses: 2550, count: 1, pending: 1}
    assert Ledger.list_transactions(%{}) |> Enum.map(& &1.flow_type) == ["expense"]
    assert Ledger.spending_by(:category) == [{"Mercado", 2550}]
    assert Ledger.filter_options().banks == ["Nubank"]
    assert Ledger.filter_options().sources == ["cartão"]
  end

  test "sorts expenses by date or value", %{conn: conn} do
    {period_start, _period_end} = Financeiro.MonthPeriod.current_bounds()

    transaction_fixture(%{
      occurred_on: period_start,
      amount_cents: 30_000,
      description: "Despesa antiga maior"
    })

    transaction_fixture(%{
      occurred_on: Date.add(period_start, 1),
      amount_cents: 10_000,
      description: "Despesa intermediária menor"
    })

    transaction_fixture(%{
      occurred_on: Date.add(period_start, 2),
      amount_cents: 20_000,
      description: "Despesa recente média"
    })

    {:ok, view, html} = live(conn, ~p"/")

    assert_in_order(html, [
      "Despesa recente média",
      "Despesa intermediária menor",
      "Despesa antiga maior"
    ])

    html = render_change(view, "filter", %{"filters" => %{"sort" => "date_asc"}})

    assert_in_order(html, [
      "Despesa antiga maior",
      "Despesa intermediária menor",
      "Despesa recente média"
    ])

    html = render_change(view, "filter", %{"filters" => %{"sort" => "value_desc"}})

    assert_in_order(html, [
      "Despesa antiga maior",
      "Despesa recente média",
      "Despesa intermediária menor"
    ])

    html = render_change(view, "filter", %{"filters" => %{"sort" => "value_asc"}})

    assert_in_order(html, [
      "Despesa intermediária menor",
      "Despesa recente média",
      "Despesa antiga maior"
    ])
  end

  test "shows the full expense history by default and offers financial-month shortcuts", %{
    conn: conn
  } do
    {current_start, _current_end} = Financeiro.MonthPeriod.current_bounds()
    previous_start = Financeiro.MonthPeriod.previous_start(current_start)
    older_start = Financeiro.MonthPeriod.previous_start(previous_start)

    transaction_fixture(%{occurred_on: current_start, description: "Despesa deste mês"})
    transaction_fixture(%{occurred_on: previous_start, description: "Despesa do mês anterior"})
    transaction_fixture(%{occurred_on: older_start, description: "Despesa histórica"})

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Despesa deste mês"
    assert html =~ "Despesa do mês anterior"
    assert html =~ "Despesa histórica"
    assert has_element?(view, ".period-quick-filter button.active", "Todo o histórico")

    current_html =
      view
      |> element(".period-quick-filter button[phx-value-period=current]")
      |> render_click()

    assert current_html =~ "Despesa deste mês"
    refute current_html =~ "Despesa do mês anterior"
    refute current_html =~ "Despesa histórica"

    previous_html =
      view
      |> element(".period-quick-filter button[phx-value-period=previous]")
      |> render_click()

    refute previous_html =~ "Despesa deste mês"
    assert previous_html =~ "Despesa do mês anterior"
    refute previous_html =~ "Despesa histórica"

    all_html =
      view
      |> element(".period-quick-filter button[phx-value-period=all]")
      |> render_click()

    assert all_html =~ "Despesa deste mês"
    assert all_html =~ "Despesa do mês anterior"
    assert all_html =~ "Despesa histórica"
  end

  test "shows the full income history by default and offers financial-month shortcuts", %{
    conn: conn
  } do
    {current_start, _current_end} = Financeiro.MonthPeriod.current_bounds()
    previous_start = Financeiro.MonthPeriod.previous_start(current_start)
    older_start = Financeiro.MonthPeriod.previous_start(previous_start)

    income_attrs = %{flow_type: "income", amount_cents: -100_000, source_type: "conta"}

    transaction_fixture(
      Map.merge(income_attrs, %{occurred_on: current_start, description: "Entrada deste mês"})
    )

    transaction_fixture(
      Map.merge(income_attrs, %{
        occurred_on: previous_start,
        description: "Entrada do mês anterior"
      })
    )

    transaction_fixture(
      Map.merge(income_attrs, %{occurred_on: older_start, description: "Entrada histórica"})
    )

    {:ok, view, html} = live(conn, ~p"/income")

    assert html =~ "Entrada deste mês"
    assert html =~ "Entrada do mês anterior"
    assert html =~ "Entrada histórica"
    assert has_element?(view, ".period-quick-filter button.active", "Todo o histórico")

    current_html =
      view
      |> element(".period-quick-filter button[phx-value-period=current]")
      |> render_click()

    assert current_html =~ "Entrada deste mês"
    refute current_html =~ "Entrada do mês anterior"
    refute current_html =~ "Entrada histórica"

    previous_html =
      view
      |> element(".period-quick-filter button[phx-value-period=previous]")
      |> render_click()

    refute previous_html =~ "Entrada deste mês"
    assert previous_html =~ "Entrada do mês anterior"
    refute previous_html =~ "Entrada histórica"
  end

  test "separates income while refunds reduce the single expense total", %{conn: conn} do
    transaction_fixture()

    transaction_fixture(%{
      description: "Estorno Oba Hortifruti",
      merchant_key: "estorno oba hortifruti",
      flow_type: "refund",
      amount_cents: -500
    })

    transaction_fixture(%{
      description: "Salário recebido",
      merchant_key: "salario recebido",
      flow_type: "income",
      amount_cents: -10_000,
      source_type: "conta"
    })

    {:ok, _expenses_view, expenses_html} = live(conn, ~p"/")
    assert expenses_html =~ "Oba Hortifruti"
    assert expenses_html =~ "Estorno Oba Hortifruti"
    refute expenses_html =~ "Salário recebido"
    assert expenses_html =~ "R$ 20,50"

    {:ok, income_view, income_html} = live(conn, ~p"/income")
    assert income_html =~ "Salário recebido"
    refute income_html =~ "Estorno Oba Hortifruti"
    refute has_element?(income_view, "th", "Categoria")
  end

  test "switches from the joined panorama to category-segmented daily rhythm", %{conn: conn} do
    transaction_fixture(%{category: "Mercado"})
    transaction_fixture(%{category: "Casa", amount_cents: 1800})

    transaction_fixture(%{
      category: "Mercado",
      amount_cents: -300,
      flow_type: "refund"
    })

    {:ok, view, html} = live(conn, ~p"/insights")
    assert html =~ "Realizado e projeção"
    assert has_element?(view, "#forecast-total")
    refute has_element?(view, "button[phx-value-mode=mapa]")
    refute has_element?(view, "button[phx-value-mode=projecao]")

    rhythm_html = view |> element("button[phx-value-mode=ritmo]") |> render_click()
    assert rhythm_html =~ "Ritmo diário"
    assert has_element?(view, ".day-stack i[data-category=Mercado]")
    assert has_element?(view, ".day-stack i[data-category=Casa]")
    assert has_element?(view, ".day-stack i.refund")
  end

  test "forecasts the current fifth-to-fourth period for every category", %{conn: conn} do
    today = Financeiro.MonthPeriod.current_date()
    {period_start, period_end} = Financeiro.MonthPeriod.bounds(today)
    elapsed_days = Date.diff(today, period_start) + 1
    days_in_period = Date.diff(period_end, period_start) + 1

    transaction_fixture(%{occurred_on: today, amount_cents: 2400, category: "Mercado"})
    transaction_fixture(%{occurred_on: today, amount_cents: 1200, category: "Casa"})

    transaction_fixture(%{
      occurred_on: today,
      amount_cents: -400,
      category: "Mercado",
      flow_type: "refund"
    })

    transaction_fixture(%{
      occurred_on: Date.add(period_start, -1),
      amount_cents: 99_999,
      category: "Extras"
    })

    {:ok, view, html} = live(conn, ~p"/insights")

    expected_total = round(3200 * days_in_period / elapsed_days)

    assert html =~ "Realizado e projeção"
    assert html =~ "#{elapsed_days} dias do ciclo"

    assert html =~
             "Mês financeiro de #{FinanceiroWeb.Format.short_date(period_start)} a #{FinanceiroWeb.Format.short_date(period_end)}"

    assert has_element?(view, "#forecast-actual", "R$ 32,00")
    assert has_element?(view, "#forecast-total", FinanceiroWeb.Format.money(expected_total))
    assert length(Regex.scan(~r/class="forecast-row"/, html)) == length(Transaction.categories())
    assert html =~ "--category-color: #16A34A"
    assert html =~ "--category-color: #2563EB"
  end

  defp transaction_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          occurred_on: Financeiro.MonthPeriod.current_bounds() |> elem(0),
          amount_cents: 2550,
          description: "Oba Hortifruti",
          merchant_key: "oba hortifruti",
          category: "Mercado",
          classification_source: "rule",
          classification_confidence: 82,
          review_status: "pending",
          bank: "Nubank",
          owner: "Thiago",
          account_ref: "Cartão",
          source_type: "cartão",
          source_file: "teste.csv",
          fingerprint: "fixture-#{System.unique_integer([:positive])}",
          raw_data: %{}
        },
        overrides
      )

    %Transaction{} |> Transaction.changeset(attrs) |> Repo.insert!()
  end

  defp assert_in_order(html, descriptions) do
    positions =
      Enum.map(descriptions, fn description ->
        {position, _length} = :binary.match(html, description)
        position
      end)

    assert positions == Enum.sort(positions)
  end
end
