defmodule FinanceiroWeb.TransactionsLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    filters = %{
      "from" => "2026-08-01",
      "to" => "",
      "search" => "",
      "category" => "all",
      "owner" => "all",
      "bank" => "all",
      "origin" => "all",
      "status" => "all",
      "direction" => "spending",
      "sort" => "date_desc"
    }

    {:ok, load(socket, filters)}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket),
    do: {:noreply, load(socket, filters)}

  def handle_event("review", %{"id" => id}, socket) do
    transaction = Ledger.get_transaction!(id)
    {:ok, _} = Ledger.review_transaction(transaction, transaction.category)

    {:noreply,
     socket
     |> put_flash(:info, "Categoria confirmada")
     |> load(socket.assigns.filters)}
  end

  def handle_event(
        "category",
        %{"transaction_id" => id, "category" => category},
        socket
      ) do
    transaction = Ledger.get_transaction!(id)
    {:ok, _} = Ledger.change_category(transaction, category)

    {:noreply,
     socket
     |> put_flash(:info, "Categoria alterada para #{category} e salva no banco de dados")
     |> load(socket.assigns.filters)}
  end

  def handle_event("undo_or_reopen", %{"id" => id}, socket) do
    transaction = Ledger.get_transaction!(id)

    message =
      if transaction.undo_action_id do
        {:ok, count} = Ledger.undo_transaction(transaction)
        undo_message(count)
      else
        {:ok, _} = Ledger.reopen_transaction(transaction)
        "Lançamento reaberto para revisão"
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> load(socket.assigns.filters)}
  end

  def handle_event("undo", _params, socket) do
    {:ok, count} = Ledger.undo_action(Ledger.latest_undo_action())

    {:noreply,
     socket
     |> put_flash(:info, undo_message(count))
     |> load(socket.assigns.filters)}
  end

  defp load(socket, filters) do
    assign(socket,
      page_title: "Despesas",
      filters: filters,
      transactions: Ledger.list_transactions(filters),
      totals: Ledger.totals(),
      undo_available: not is_nil(Ledger.latest_undo_action()),
      options: Ledger.filter_options(),
      categories: Ledger.categories()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="transactions" pending={@totals.pending}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">Desde 01 de agosto de 2026</p>
          <h1>Despesas</h1>
          <p>Compras e estornos, já consolidados no mesmo total.</p>
        </div>
        <div class="heading-actions">
          <button :if={@undo_available} phx-click="undo" class="secondary-action">
            <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Desfazer última
          </button>
          <.link navigate={~p"/review"} class="primary-action">
            Revisar {@totals.pending} pendentes <.icon name="hero-arrow-right-mini" class="size-4" />
          </.link>
        </div>
      </div>

      <section class="summary-strip summary-strip-three">
        <div><span>Saídas líquidas</span><strong>{Format.money(@totals.expenses)}</strong></div>
        <div><span>Lançamentos</span><strong>{@totals.count}</strong></div>
        <div><span>Para revisar</span><strong class="attention">{@totals.pending}</strong></div>
      </section>

      <form phx-change="filter" class="filter-panel">
        <div class="search-field">
          <.icon name="hero-magnifying-glass-mini" class="size-5" />
          <input
            name="filters[search]"
            value={@filters["search"]}
            placeholder="Buscar descrição..."
            phx-debounce="250"
          />
        </div>
        <select name="filters[category]">
          <option value="all">Todas as categorias</option>
          <option
            :for={category <- @categories}
            value={category}
            selected={@filters["category"] == category}
          >
            {category}
          </option>
        </select>
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
        <select name="filters[status]">
          <option value="all">Revisados e pendentes</option>
          <option value="pending" selected={@filters["status"] == "pending"}>
            Aguardando revisão
          </option>
          <option value="reviewed" selected={@filters["status"] == "reviewed"}>Revisados</option>
        </select>
        <select name="filters[direction]">
          <option value="spending" selected={@filters["direction"] == "spending"}>
            Despesas e estornos
          </option>
          <option value="expenses" selected={@filters["direction"] == "expenses"}>Só despesas</option>
          <option value="refunds" selected={@filters["direction"] == "refunds"}>Só estornos</option>
        </select>
        <select name="filters[sort]" aria-label="Ordenar despesas">
          <option value="date_desc" selected={@filters["sort"] in [nil, "date_desc"]}>
            Data · mais recentes
          </option>
          <option value="date_asc" selected={@filters["sort"] == "date_asc"}>
            Data · mais antigas
          </option>
          <option value="value_desc" selected={@filters["sort"] == "value_desc"}>
            Valor · maior primeiro
          </option>
          <option value="value_asc" selected={@filters["sort"] == "value_asc"}>
            Valor · menor primeiro
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
        <span>{length(@transactions)} lançamentos exibidos</span>
        <span><i class="status-dot pending"></i> automático, falta confirmar</span>
      </div>

      <div class="transaction-table-wrap">
        <table class="transaction-table">
          <thead>
            <tr>
              <th>Data</th>
              <th>Descrição</th>
              <th>Pessoa / origem</th>
              <th>Categoria</th>
              <th class="amount">Valor</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={transaction <- @transactions} class={transaction.review_status}>
              <td class="date-cell">{Format.date(transaction.occurred_on)}</td>
              <td>
                <div class="description-cell">
                  <i class={["status-dot", transaction.review_status]}></i>
                  <div>
                    <strong>{transaction.description}</strong><span>{flow_label(transaction.flow_type)} · {transaction.account_ref}</span>
                  </div>
                </div>
              </td>
              <td>
                <strong class="owner-name">{transaction.owner}</strong><span class="bank-label">{transaction.bank} · {origin_label(transaction)}</span>
              </td>
              <td>
                <form phx-change="category" class="category-form">
                  <input type="hidden" name="transaction_id" value={transaction.id} />
                  <select
                    class={"category-select category-#{String.downcase(transaction.category)}"}
                    name="category"
                  >
                    <option
                      :for={category <- @categories}
                      value={category}
                      selected={category == transaction.category}
                    >
                      {category}
                    </option>
                  </select>
                </form>
                <span class="confidence">
                  {transaction.classification_confidence}% · {classification_label(transaction)}
                </span>
              </td>
              <td class={["amount", transaction.amount_cents < 0 && "credit"]}>
                {Format.money(transaction.amount_cents)}
              </td>
              <td>
                <div class="row-actions">
                  <button
                    :if={transaction.review_status == "pending"}
                    phx-click="review"
                    phx-value-id={transaction.id}
                    class="review-check"
                    title="Confirmar categoria"
                  >
                    <.icon name="hero-check-mini" class="size-4" />
                  </button>
                  <button
                    :if={transaction.review_status == "reviewed"}
                    phx-click="undo_or_reopen"
                    phx-value-id={transaction.id}
                    class="row-undo"
                    title={
                      if transaction.undo_action_id,
                        do: "Desfazer a última alteração",
                        else: "Reabrir para revisar novamente"
                    }
                  >
                    <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
                  </button>
                  <details class="raw-details">
                    <summary title="Ver dados de origem">•••</summary>
                    <div>
                      <strong>{transaction.source_file}</strong><pre>{Jason.encode!(transaction.raw_data, pretty: true)}</pre>
                    </div>
                  </details>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div :if={@transactions == []} class="empty-state">
          <.icon name="hero-funnel-mini" class="size-8" />
          <strong>
            Nenhum lançamento encontrado
          </strong>
          <span>Tente remover algum filtro.</span>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp classification_label(%{classification_source: "manual", review_status: "pending"}),
    do: "salvo · falta confirmar"

  defp classification_label(%{classification_source: "manual", review_status: "reviewed"}),
    do: "salvo no banco"

  defp classification_label(%{classification_source: "history"}), do: "histórico"
  defp classification_label(%{classification_source: "rule"}), do: "regra"
  defp classification_label(%{classification_source: "luna"}), do: "Luna"
  defp classification_label(%{classification_source: "luna_error"}), do: "Luna pendente"
  defp classification_label(_), do: "estimativa"

  defp flow_label("expense"), do: "despesa"
  defp flow_label("refund"), do: "estorno"

  defp origin_label(%{source_type: source}), do: source

  defp undo_message(1), do: "Última confirmação desfeita"
  defp undo_message(count), do: "#{count} confirmações semelhantes desfeitas"
end
