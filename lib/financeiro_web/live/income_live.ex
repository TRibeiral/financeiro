defmodule FinanceiroWeb.IncomeLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Ledger
  alias Financeiro.MonthPeriod
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    filters =
      Map.merge(MonthPeriod.filters(), %{
        "search" => "",
        "owner" => "all",
        "bank" => "all",
        "origin" => "all"
      })

    {:ok, load(socket, filters, MonthPeriod.current_bounds())}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket),
    do: {:noreply, load(socket, filters, socket.assigns.period)}

  defp load(socket, filters, period) do
    assign(socket,
      page_title: "Entradas",
      period: period,
      filters: filters,
      transactions: Ledger.list_income(filters),
      totals: Ledger.income_totals(filters),
      options: Ledger.income_filter_options(),
      pending: Ledger.pending_count()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="income" pending={@pending}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">
            Recebimentos · {Format.short_date(elem(@period, 0))} a {Format.short_date(
              elem(@period, 1)
            )}
          </p>
          <h1>Entradas</h1>
          <p>Salários e depósitos recebidos, sem categorias de despesa.</p>
        </div>
      </div>

      <section class="summary-strip summary-strip-two">
        <div>
          <span>Total de entradas</span><strong class="positive">{Format.money(@totals.total)}</strong>
        </div>
        <div><span>Recebimentos</span><strong>{@totals.count}</strong></div>
      </section>

      <form phx-change="filter" class="filter-panel income-filter-panel">
        <div class="search-field">
          <.icon name="hero-magnifying-glass-mini" class="size-5" />
          <input
            name="filters[search]"
            value={@filters["search"]}
            placeholder="Buscar entrada..."
            phx-debounce="250"
          />
        </div>
        <select name="filters[owner]">
          <option value="all">Todas as pessoas</option>
          <option :for={owner <- @options.owners} value={owner} selected={@filters["owner"] == owner}>
            {owner}
          </option>
        </select>
        <select name="filters[bank]">
          <option value="all">Todos os bancos</option>
          <option :for={bank <- @options.banks} value={bank} selected={@filters["bank"] == bank}>
            {bank}
          </option>
        </select>
        <select name="filters[origin]">
          <option value="all">Todas as origens</option>
          <option
            :for={source <- @options.sources}
            value={source}
            selected={@filters["origin"] == source}
          >
            {String.capitalize(source)}
          </option>
        </select>
        <label class="date-filter">
          <span>De</span> <input type="date" name="filters[from]" value={@filters["from"]} />
        </label>
        <label class="date-filter">
          <span>Até</span> <input type="date" name="filters[to]" value={@filters["to"]} />
        </label>
      </form>

      <div class="table-meta">
        <span>{length(@transactions)} entradas exibidas</span>
        <span>Estornos ficam em Despesas e já reduzem o total de saídas</span>
      </div>

      <div class="transaction-table-wrap">
        <table class="transaction-table income-table">
          <thead>
            <tr>
              <th>Data</th>
              <th>Descrição</th>
              <th>Pessoa / origem</th>
              <th class="amount">Valor</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={transaction <- @transactions}>
              <td class="date-cell">{Format.date(transaction.occurred_on)}</td>
              <td>
                <div class="description-cell">
                  <i class="income-marker">+</i>
                  <div>
                    <strong>{transaction.description}</strong><span>{transaction.source_type} · {transaction.account_ref}</span>
                  </div>
                </div>
              </td>
              <td>
                <strong class="owner-name">{transaction.owner}</strong><span class="bank-label">{transaction.bank} · {transaction.source_type}</span>
              </td>
              <td class="amount credit">{Format.money(abs(transaction.amount_cents))}</td>
              <td>
                <details class="raw-details">
                  <summary title="Ver dados de origem">•••</summary>
                  <div>
                    <strong>{transaction.source_file}</strong><pre>{Jason.encode!(transaction.raw_data, pretty: true)}</pre>
                  </div>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@transactions == []} class="empty-state">
          <.icon name="hero-arrow-trending-up-mini" class="size-8" />
          <strong>Nenhuma entrada encontrada</strong>
          <span>Tente remover algum filtro.</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
