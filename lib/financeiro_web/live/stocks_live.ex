defmodule FinanceiroWeb.StocksLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Investments
  alias Financeiro.Investments.Stock
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        page_title: "Ações",
        pending: Ledger.pending_count(),
        view: "all",
        sort: "tier_position",
        search: "",
        show_new: false,
        editing_id: nil,
        edit_form: nil,
        refreshing: false
      )
      |> new_form()
      |> reload()

    {:ok, socket}
  end

  @impl true
  def handle_event("set_view", %{"view" => view}, socket)
      when view in ~w(all owned watched unread) do
    {:noreply, socket |> assign(view: view) |> filter_stocks()}
  end

  def handle_event("set_sort", %{"sort" => sort}, socket)
      when sort in ~w(tier_position position) do
    {:noreply, socket |> assign(sort: sort) |> filter_stocks()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(search: search) |> filter_stocks()}
  end

  def handle_event("toggle_new", _params, socket) do
    {:noreply,
     socket |> assign(show_new: !socket.assigns.show_new, editing_id: nil) |> new_form()}
  end

  def handle_event("create", %{"stock" => attrs}, socket) do
    case Investments.create_stock(attrs) do
      {:ok, _stock} ->
        {:noreply,
         socket
         |> put_flash(:info, "Ação adicionada")
         |> assign(show_new: false)
         |> new_form()
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, new_form: to_form(changeset, as: :stock))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    stock = Investments.get_stock!(id)

    {:noreply,
     assign(socket,
       editing_id: stock.id,
       show_new: false,
       edit_form: to_form(Investments.change_stock(stock), as: :stock)
     )}
  end

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing_id: nil, edit_form: nil)}

  def handle_event("update", %{"stock_id" => id, "stock" => attrs}, socket) do
    stock = Investments.get_stock!(id)

    case Investments.update_stock(stock, attrs) do
      {:ok, _stock} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{stock.ticker} atualizado")
         |> assign(editing_id: nil, edit_form: nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, editing_id: stock.id, edit_form: to_form(changeset, as: :stock))}
    end
  end

  def handle_event("record_purchase", %{"id" => id}, socket) do
    stock = Investments.get_stock!(id)
    {:ok, _stock} = Investments.record_purchase(stock)
    {:noreply, socket |> put_flash(:info, "Compra de #{stock.ticker} marcada") |> reload()}
  end

  def handle_event("check_today", %{"id" => id}, socket) do
    stock = Investments.get_stock!(id)
    {:ok, _stock} = Investments.check_today(stock)
    {:noreply, reload(socket)}
  end

  def handle_event("refresh_quotes", _params, %{assigns: %{refreshing: true}} = socket),
    do: {:noreply, socket}

  def handle_event("refresh_quotes", _params, socket) do
    tickers =
      socket.assigns.stocks
      |> Enum.filter(&(&1.shares > 0))
      |> Enum.map(& &1.ticker)

    provider = Application.fetch_env!(:financeiro, :stock_quote_provider)

    {:noreply,
     socket
     |> assign(refreshing: true)
     |> start_async(:refresh_quotes, fn -> provider.fetch_quotes(tickers) end)}
  end

  @impl true
  def handle_async(:refresh_quotes, {:ok, {:ok, quotes}}, socket) do
    case Investments.apply_quotes(quotes) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(refreshing: false)
         |> put_flash(:info, quote_success_message(count))
         |> reload()}

      {:error, reason} ->
        {:noreply, quote_error(socket, inspect(reason))}
    end
  end

  def handle_async(:refresh_quotes, {:ok, {:error, reason}}, socket),
    do: {:noreply, quote_error(socket, reason)}

  def handle_async(:refresh_quotes, {:exit, reason}, socket),
    do: {:noreply, quote_error(socket, inspect(reason))}

  defp quote_error(socket, reason) do
    socket
    |> assign(refreshing: false)
    |> put_flash(:error, "Não foi possível atualizar as cotações: #{reason}")
  end

  defp quote_success_message(1), do: "1 cotação atualizada com Luna"
  defp quote_success_message(count), do: "#{count} cotações atualizadas com Luna"

  defp reload(socket) do
    stocks = Investments.list_stocks()

    socket
    |> assign(
      stocks: stocks,
      summary: Investments.summary(stocks),
      current_result: Investments.current_result()
    )
    |> filter_stocks()
  end

  defp filter_stocks(socket) do
    search = socket.assigns.search |> String.trim() |> String.downcase()

    filtered =
      socket.assigns.stocks
      |> Enum.filter(fn stock ->
        case socket.assigns.view do
          "owned" -> stock.shares > 0
          "watched" -> stock.shares == 0
          "unread" -> stock.last_result != socket.assigns.current_result
          _ -> true
        end
      end)
      |> Enum.filter(fn stock ->
        search == "" or String.contains?(String.downcase("#{stock.name} #{stock.ticker}"), search)
      end)
      |> sort_stocks(socket.assigns.sort)

    assign(socket, filtered_stocks: filtered)
  end

  defp sort_stocks(stocks, sort) do
    Enum.sort(stocks, fn left, right ->
      left_key = sort_key(left, sort)
      right_key = sort_key(right, sort)

      if left_key == right_key do
        String.downcase(left.name) <= String.downcase(right.name)
      else
        left_key > right_key
      end
    end)
  end

  defp sort_key(stock, "position"), do: stock_value(stock)
  defp sort_key(stock, "tier_position"), do: {stock.tier, stock_value(stock)}

  defp new_form(socket) do
    stock = %Stock{last_result: Investments.current_result(), checked_on: Date.utc_today()}
    assign(socket, new_form: to_form(Investments.change_stock(stock), as: :stock))
  end

  defp tier_name(-1), do: "Vender"
  defp tier_name(tier), do: "Tier #{tier}"

  defp stock_value(stock), do: Investments.holding_value(stock)
  defp stock_percent(stock, total), do: Investments.percentage(stock, total)
  defp percent(value), do: :erlang.float_to_binary(value, decimals: 1) <> "%"

  # The purchase count is unlimited; only its visual saturation is capped.
  defp purchase_visual_heat(heat), do: min(heat, 10)
  defp purchase_label(1), do: "1 compra recente"
  defp purchase_label(count), do: "#{count} compras recentes"

  defp result_current?(stock, current_result), do: stock.last_result == current_result

  defp quote_time(nil), do: "Ainda sem cotação"

  defp quote_time(datetime) do
    date = DateTime.to_date(datetime)
    "Atualizada em #{Format.short_date(date)} às #{pad(datetime.hour)}:#{pad(datetime.minute)}"
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp field_error(form, field) do
    case Keyword.get(form.errors, field) do
      nil -> nil
      {message, _opts} -> message
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="stocks" pending={@pending}>
      <div class="page-heading stocks-heading">
        <div>
          <p class="eyebrow">Carteira & radar</p>
          <h1>Ações brasileiras</h1>
          <p>Patrimônio, convicção e resultados acompanhados no mesmo lugar.</p>
        </div>
        <div class="heading-actions">
          <button phx-click="toggle_new" class="secondary-action">
            <.icon name="hero-plus-mini" class="size-4" /> Nova ação
          </button>
          <button
            id="refresh-quotes"
            phx-click="refresh_quotes"
            class="primary-action quote-refresh"
            disabled={@stocks == [] or @refreshing}
          >
            <.icon name="hero-arrow-path-mini" class={["size-4", @refreshing && "spin"]} />
            {if @refreshing, do: "Luna pesquisando…", else: "Atualizar cotações"}
          </button>
        </div>
      </div>

      <section class="portfolio-hero">
        <div class="portfolio-total">
          <span>Patrimônio em ações</span>
          <strong>{Format.money(@summary.total)}</strong>
          <small>
            <.icon name="hero-lock-closed-mini" class="size-3" /> Cotações ficam salvas localmente
          </small>
        </div>
        <div class="portfolio-metrics">
          <div><span>Na carteira</span><strong>{@summary.owned}</strong><small>posições</small></div>
          <div>
            <span>No radar</span><strong>{@summary.watched}</strong><small>sem posição</small>
          </div>
          <div>
            <span>Resultados lidos</span><strong>{@summary.current_results}<i>/ {length(@stocks)}</i></strong><small>{@current_result}</small>
          </div>
          <div class={@summary.results_to_read > 0 && "needs-attention"}>
            <span>Para ler</span><strong>{@summary.results_to_read}</strong><small>resultados</small>
          </div>
        </div>
      </section>

      <section :if={@show_new} class="stock-form-card stock-new-card">
        <div class="stock-form-title">
          <div>
            <span class="stock-form-icon">+</span>
            <div>
              <strong>Adicionar ao radar</strong><small>Quantidade zero mantém a ação apenas em acompanhamento.</small>
            </div>
          </div>
          <button type="button" phx-click="toggle_new" aria-label="Fechar">×</button>
        </div>
        <.stock_form form={@new_form} submit="create" id="new-stock-form" />
      </section>

      <div class="stock-toolbar">
        <div class="stock-tabs" role="tablist">
          <button phx-click="set_view" phx-value-view="all" class={@view == "all" && "active"}>
            Todas <i>{length(@stocks)}</i>
          </button>
          <button phx-click="set_view" phx-value-view="owned" class={@view == "owned" && "active"}>
            Carteira <i>{@summary.owned}</i>
          </button>
          <button phx-click="set_view" phx-value-view="watched" class={@view == "watched" && "active"}>
            Radar <i>{@summary.watched}</i>
          </button>
          <button phx-click="set_view" phx-value-view="unread" class={@view == "unread" && "active"}>
            Para ler <i>{@summary.results_to_read}</i>
          </button>
        </div>
        <div class="stock-toolbar-actions">
          <form id="stock-sort-form" phx-change="set_sort" class="stock-sort">
            <.icon name="hero-arrows-up-down-mini" class="size-4" />
            <select name="sort" aria-label="Ordenar ações">
              <option value="tier_position" selected={@sort == "tier_position"}>
                Tier ↓ · Posição ↓
              </option>
              <option value="position" selected={@sort == "position"}>Posição ↓</option>
            </select>
          </form>
          <form phx-change="search" class="stock-search">
            <.icon name="hero-magnifying-glass-mini" class="size-4" />
            <input
              name="search"
              value={@search}
              placeholder="Buscar nome ou ticker"
              phx-debounce="200"
            />
          </form>
        </div>
      </div>

      <div class="stocks-layout">
        <section class="stocks-list">
          <div class="stocks-list-head">
            <div>
              <strong>{length(@filtered_stocks)} ações</strong><span>Valor total = cotação × quantidade</span>
            </div>
            <span class="tier-legend"><i></i> tier <b></b> compra recente</span>
          </div>

          <article
            :for={stock <- @filtered_stocks}
            id={"stock-#{stock.id}"}
            class={["stock-card", "tier-#{stock.tier}", stock.purchase_heat > 0 && "purchased"]}
            style={
              stock.purchase_heat > 0 &&
                "--purchase-heat: #{purchase_visual_heat(stock.purchase_heat)}"
            }
          >
            <%= if @editing_id == stock.id do %>
              <div class="stock-form-title compact">
                <div>
                  <span class="ticker-avatar">{String.first(stock.ticker)}</span>
                  <div>
                    <strong>Editar {stock.ticker}</strong><small>Trocar o resultado trimestral remove a marcação rosa de compras.</small>
                  </div>
                </div>
                <button type="button" phx-click="cancel_edit" aria-label="Cancelar">×</button>
              </div>
              <.stock_form
                form={@edit_form}
                submit="update"
                id={"edit-stock-#{stock.id}"}
                stock_id={stock.id}
              />
            <% else %>
              <div class="stock-main">
                <div class="stock-identity">
                  <span class="ticker-avatar">{String.first(stock.ticker)}</span>
                  <div>
                    <strong>{stock.name}</strong><span>{stock.ticker} · {if stock.shares > 0, do: "Carteira", else: "No radar"}</span>
                  </div>
                </div>
                <div class="stock-quantity">
                  <span>Quantidade</span><strong>{stock.shares}</strong>
                </div>
                <div class="stock-quote">
                  <span>Cotação</span><strong>{if stock.quote_cents, do: Format.money(stock.quote_cents), else: "—"}</strong><small title={
                    stock.quote_source
                  }>{quote_time(stock.quote_refreshed_at)}</small>
                </div>
                <div class="stock-position">
                  <span>Posição</span><strong>{Format.money(stock_value(stock))}</strong><small>{percent(stock_percent(stock, @summary.total))} da carteira</small>
                </div>
                <div class="stock-review">
                  <span>Resultado lido</span>
                  <strong class={result_current?(stock, @current_result) && "current"}>
                    {stock.last_result}
                  </strong>
                  <small>
                    {if result_current?(stock, @current_result), do: "em dia", else: "pendente"}
                  </small>
                </div>
                <div class="stock-checked">
                  <span>Última olhada</span><strong>{if stock.checked_on, do: Format.date(stock.checked_on), else: "—"}</strong>
                  <button phx-click="check_today" phx-value-id={stock.id}>Marcar hoje</button>
                </div>
                <div class={["stock-tier", "tier-badge-#{stock.tier}"]}>
                  <span>{tier_name(stock.tier)}</span><strong>{stock.tier}</strong>
                </div>
                <div class="stock-actions">
                  <button
                    class="buy-action"
                    phx-click="record_purchase"
                    phx-value-id={stock.id}
                    title="Marcar uma compra recente"
                  >
                    <.icon name="hero-shopping-bag-mini" class="size-4" /><span>Comprei</span>
                  </button>
                  <button phx-click="edit" phx-value-id={stock.id} title="Editar ação">
                    <.icon name="hero-pencil-square-mini" class="size-4" /><span>Editar</span>
                  </button>
                </div>
              </div>
              <div :if={stock.purchase_heat > 0} class="purchase-note">
                <span>
                  <.icon name="hero-arrow-trending-up-mini" class="size-3" />
                  {purchase_label(stock.purchase_heat)}
                </span>
                <small>A marca desaparece ao registrar o próximo resultado trimestral.</small>
              </div>
            <% end %>
          </article>

          <div :if={@filtered_stocks == []} class="stocks-empty">
            <span><.icon name="hero-presentation-chart-line" class="size-8" /></span>
            <strong>
              {if @stocks == [], do: "Sua carteira começa aqui", else: "Nenhuma ação neste filtro"}
            </strong>
            <p>
              {if @stocks == [],
                do:
                  "Adicione as ações que você possui ou acompanha. Não é preciso saber a quantidade agora.",
                else: "Tente outra busca ou mude a visualização."}
            </p>
            <button :if={@stocks == []} phx-click="toggle_new" class="primary-action">
              Adicionar primeira ação
            </button>
          </div>
        </section>

        <aside class="allocation-card">
          <div class="allocation-title">
            <div><span>Distribuição</span><strong>Peso da carteira</strong></div>
            <i>100%</i>
          </div>
          <div :if={@summary.total > 0} class="allocation-list">
            <div :for={stock <- Enum.filter(@stocks, &(stock_value(&1) > 0))} class="allocation-row">
              <div>
                <span>{stock.ticker}</span><strong>{percent(stock_percent(stock, @summary.total))}</strong>
              </div>
              <div class="allocation-track">
                <i style={"width: #{stock_percent(stock, @summary.total)}%"}></i>
              </div>
              <small>{Format.money(stock_value(stock))}</small>
            </div>
          </div>
          <div :if={@summary.total == 0} class="allocation-empty">
            <span>∿</span><strong>Aguardando posições</strong>
            <p>Preencha as quantidades e atualize as cotações para ver a distribuição.</p>
          </div>
          <div class="allocation-foot">
            <span><i class="quote-dot"></i>{@summary.without_quote} sem cotação</span>
            <small>Codex · ChatGPT · {Financeiro.Investments.LunaQuoteProvider.model()}</small>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  attr :form, :map, required: true
  attr :submit, :string, required: true
  attr :id, :string, required: true
  attr :stock_id, :integer, default: nil

  defp stock_form(assigns) do
    ~H"""
    <form id={@id} phx-submit={@submit} class="stock-editor">
      <input :if={@stock_id} type="hidden" name="stock_id" value={@stock_id} />
      <label class="wide">
        <span>Nome da empresa</span>
        <input name={@form[:name].name} value={@form[:name].value} placeholder="Petrobras" required />
        <small :if={field_error(@form, :name)}>
          {field_error(@form, :name)}
        </small>
      </label>
      <label>
        <span>Ticker B3</span>
        <input
          name={@form[:ticker].name}
          value={@form[:ticker].value}
          placeholder="PETR4"
          autocapitalize="characters"
          required
        /><small :if={field_error(@form, :ticker)}>{field_error(@form, :ticker)}</small>
      </label>
      <label>
        <span>Quantidade</span>
        <input
          type="number"
          min="0"
          step="1"
          name={@form[:shares].name}
          value={@form[:shares].value || 0}
          required
        /><small :if={field_error(@form, :shares)}>{field_error(@form, :shares)}</small>
      </label>
      <label>
        <span>Resultado lido</span>
        <input
          name={@form[:last_result].name}
          value={@form[:last_result].value}
          placeholder="2T26"
          required
        /><small :if={field_error(@form, :last_result)}>{field_error(@form, :last_result)}</small>
      </label>
      <label>
        <span>Tier</span><select name={@form[:tier].name} required><option
          :for={tier <- -1..5}
          value={tier}
          selected={to_string(@form[:tier].value) == to_string(tier)}
        >{if tier == -1, do: "−1 · Vender", else: "#{tier} · #{if tier == 5, do: "Máxima convicção", else: "Tier #{tier}"}"}</option></select>
      </label>
      <label>
        <span>Última olhada</span>
        <input type="date" name={@form[:checked_on].name} value={@form[:checked_on].value} />
      </label>
      <div class="stock-editor-actions">
        <button :if={@stock_id} type="button" phx-click="cancel_edit" class="secondary-action">
          Cancelar
        </button>
        <button type="submit" class="primary-action">
          {if @stock_id, do: "Salvar alterações", else: "Adicionar ação"}
        </button>
      </div>
    </form>
    """
  end
end
