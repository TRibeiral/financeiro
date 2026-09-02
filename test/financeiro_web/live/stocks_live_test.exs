defmodule FinanceiroWeb.StocksLiveTest do
  use FinanceiroWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Financeiro.Investments
  alias Financeiro.Repo

  defmodule ControlledQuoteProvider do
    def fetch_quotes(tickers) do
      test_pid = Process.whereis(:stock_quote_test)
      send(test_pid, {:quote_started, tickers, self()})

      receive do
        {:return_quotes, result} -> result
      after
        1_000 -> {:error, "test timeout"}
      end
    end
  end

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

  test "refreshes owned-stock quotes through the configured provider", %{conn: conn} do
    {:ok, stock} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 5,
        last_result: "2T26"
      })

    {:ok, watched_stock} =
      Investments.create_stock(%{
        name: "Vale",
        ticker: "VALE3",
        shares: 0,
        tier: 2,
        last_result: "2T26"
      })

    {:ok, view, _html} = live(conn, ~p"/stocks")
    view |> element("#refresh-quotes") |> render_click()
    render_async(view, 1_000)

    refreshed = Repo.reload!(stock)
    assert refreshed.quote_cents == 3_750
    assert refreshed.quote_source == "Cotação de teste"
    assert Repo.reload!(watched_stock).quote_cents == nil
    assert Repo.reload!(watched_stock).quote_source == nil
    assert render(view) =~ "R$ 3.750,00"
    assert render(view) =~ "100.0%"
    refute render(view) =~ "allocation-card"
    assert render(view) =~ "1 cotação atualizada"
  end

  test "fetches a batch, preserves failed quotes and identifies failures", %{conn: conn} do
    original_provider = Application.fetch_env!(:financeiro, :stock_quote_provider)
    Application.put_env(:financeiro, :stock_quote_provider, ControlledQuoteProvider)
    Process.register(self(), :stock_quote_test)

    on_exit(fn ->
      Application.put_env(:financeiro, :stock_quote_provider, original_provider)

      if Process.whereis(:stock_quote_test) == self() do
        Process.unregister(:stock_quote_test)
      end
    end)

    {:ok, petrobras} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 5,
        last_result: "2T26"
      })

    {:ok, vale} =
      Investments.create_stock(%{
        name: "Vale",
        ticker: "VALE3",
        shares: 50,
        tier: 4,
        last_result: "2T26"
      })

    {:ok, 1} =
      Investments.apply_quotes([
        %{ticker: "VALE3", price_cents: 6_000, source: "Cotação anterior"}
      ])

    {:ok, view, _html} = live(conn, ~p"/stocks")
    view |> element("#refresh-quotes") |> render_click()

    assert_receive {:quote_started, tickers, task}, 500
    assert Enum.sort(tickers) == ["PETR4", "VALE3"]
    refute_receive {:quote_started, _, _}, 100

    html = render(view)
    assert html =~ "stock-position-loading-#{petrobras.id}"
    assert html =~ "stock-position-loading-#{vale.id}"

    send(task, {
      :return_quotes,
      {:ok, [%{ticker: "PETR4", price_cents: 3_750, source: "Cotação de teste"}],
       [{"VALE3", "cotação não encontrada"}]}
    })

    html = render_async(view, 1_000)

    refute html =~ "stock-position-loading-#{petrobras.id}"
    refute html =~ "stock-position-loading-#{vale.id}"
    assert html =~ "1 cotação atualizada; 1 falhou"
    assert html =~ "VALE3: cotação não encontrada"
    assert Repo.reload!(petrobras).quote_cents == 3_750
    assert Repo.reload!(vale).quote_cents == 6_000
    assert Repo.reload!(vale).quote_source == "Cotação anterior"
  end

  test "sorts by tier and position by default and can sort by position only", %{conn: conn} do
    {:ok, tier_five} =
      Investments.create_stock(%{
        name: "Tier five",
        ticker: "FIVE3",
        shares: 1,
        tier: 5,
        last_result: "2T26"
      })

    {:ok, larger_position} =
      Investments.create_stock(%{
        name: "Larger position",
        ticker: "LARG3",
        shares: 10,
        tier: 3,
        last_result: "2T26"
      })

    {:ok, smaller_position} =
      Investments.create_stock(%{
        name: "Smaller position",
        ticker: "SMAL3",
        shares: 5,
        tier: 3,
        last_result: "2T26"
      })

    {:ok, 3} =
      Investments.apply_quotes([
        %{ticker: tier_five.ticker, price_cents: 100},
        %{ticker: larger_position.ticker, price_cents: 1_000},
        %{ticker: smaller_position.ticker, price_cents: 1_000}
      ])

    {:ok, view, html} = live(conn, ~p"/stocks")

    assert stock_ids(html) == [tier_five.id, larger_position.id, smaller_position.id]

    html =
      view
      |> form("#stock-sort-form", %{"sort" => "position"})
      |> render_change()

    assert stock_ids(html) == [larger_position.id, smaller_position.id, tier_five.id]
  end

  test "shows portfolio and tier charts in a separate distribution tab", %{conn: conn} do
    {:ok, petrobras} =
      Investments.create_stock(%{
        name: "Petrobras",
        ticker: "PETR4",
        shares: 100,
        tier: 5,
        last_result: "2T26"
      })

    {:ok, vale} =
      Investments.create_stock(%{
        name: "Vale",
        ticker: "VALE3",
        shares: 50,
        tier: 3,
        last_result: "2T26"
      })

    {:ok, 2} =
      Investments.apply_quotes([
        %{ticker: petrobras.ticker, price_cents: 1_000},
        %{ticker: vale.ticker, price_cents: 1_000}
      ])

    {:ok, view, _html} = live(conn, ~p"/stocks")

    html = view |> element("#stocks-distribution-tab") |> render_click()

    assert html =~ "Participação na carteira"
    assert html =~ "Peso por posição"
    assert html =~ "Patrimônio por tier"
    assert html =~ ~s(id="allocation-PETR4")
    assert html =~ ~s(id="allocation-VALE3")
    assert html =~ ~s(id="tier-allocation-5")
    assert html =~ "66.7%"
    assert html =~ "33.3%"
    refute has_element?(view, ".stocks-layout")

    view |> element("#stocks-list-tab") |> render_click()
    assert has_element?(view, ".stocks-layout")
    assert has_element?(view, "#stock-sort-form .stock-control")
    assert has_element?(view, "#stock-search-form .stock-control")
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

    stock =
      Enum.reduce(1..5, stock, fn _, current ->
        {:ok, updated} = Investments.record_purchase(current)
        updated
      end)

    {:ok, view, _html} = live(conn, ~p"/stocks")
    html = view |> element("#stock-#{stock.id} .buy-action") |> render_click()
    assert html =~ "purchase-menu"

    html = view |> element("#stock-#{stock.id} .purchase-plus") |> render_click()
    assert html =~ "purchased"
    assert html =~ "purchase-6"
    assert html =~ "6 compras recentes"
    refute html =~ "purchase-note"
    assert Repo.reload!(stock).purchase_heat == 6

    html =
      view
      |> element("#stock-#{stock.id} .buy-action")
      |> render_click()

    assert html =~ "purchase-menu"

    html =
      view
      |> element("#stock-#{stock.id} .purchase-minus")
      |> render_click()

    assert html =~ "purchase-5"
    refute html =~ "purchase-menu"
    assert Repo.reload!(stock).purchase_heat == 5

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

  defp stock_ids(html) do
    ~r/<article id="stock-(\d+)" class="stock-card/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [id] -> String.to_integer(id) end)
  end
end
