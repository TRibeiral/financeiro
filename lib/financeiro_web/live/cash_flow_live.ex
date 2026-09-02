defmodule FinanceiroWeb.CashFlowLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.CashFlow
  alias Financeiro.Ledger
  alias Financeiro.MonthPeriod
  alias Financeiro.SumExpression
  alias FinanceiroWeb.Format

  @month_names ~w(Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro)
  @editable_fields ~w(investment_income capex)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Visão mensal",
       pending: Ledger.pending_count(),
       current_start: MonthPeriod.period_start(MonthPeriod.current_date()),
       editing: nil,
       cell_value: "",
       cell_preview: nil,
       cell_error: nil
     )
     |> reload()}
  end

  @impl true
  def handle_event("edit_cell", %{"period" => period, "field" => field}, socket)
      when field in @editable_fields do
    with {:ok, period_start} <- Date.from_iso8601(period),
         true <- Enum.any?(socket.assigns.rows, &(&1.period_start == period_start)) do
      value = expression_value(period_start, field)

      {:noreply,
       assign(socket,
         editing: {period_start, field},
         cell_value: value,
         cell_preview: parse_preview(value),
         cell_error: nil
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_cell", _params, socket), do: {:noreply, socket}

  def handle_event(
        "preview_cell",
        %{"period" => period, "field" => field, "value" => value},
        socket
      )
      when field in @editable_fields do
    case Date.from_iso8601(period) do
      {:ok, period_start} ->
        case SumExpression.parse(value) do
          {:ok, cents} ->
            {:noreply,
             assign(socket,
               editing: {period_start, field},
               cell_value: value,
               cell_preview: cents,
               cell_error: nil
             )}

          :error ->
            {:noreply,
             assign(socket,
               editing: {period_start, field},
               cell_value: value,
               cell_preview: nil,
               cell_error: "Use valores separados por +"
             )}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("preview_cell", _params, socket), do: {:noreply, socket}

  def handle_event(
        "save_cell",
        %{"period" => period, "field" => field, "value" => value},
        socket
      )
      when field in @editable_fields do
    with {:ok, period_start} <- Date.from_iso8601(period),
         {:ok, _month} <- CashFlow.save_manual(period_start, expression_attrs(field, value)) do
      {:noreply,
       socket
       |> assign(editing: nil, cell_value: "", cell_preview: nil, cell_error: nil)
       |> reload()}
    else
      {:error, _reason} ->
        {:noreply,
         assign(socket,
           cell_value: value,
           cell_preview: nil,
           cell_error: "Use valores separados por +"
         )}
    end
  end

  def handle_event("save_cell", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, cell_value: "", cell_preview: nil, cell_error: nil)}
  end

  def handle_event("sync_cash", _params, socket) do
    case CashFlow.sync_cash(socket.assigns.current_start) do
      {:ok, _month} ->
        {:noreply,
         socket
         |> put_flash(:info, "Disponível e obrigações registrados a partir do Caixa")
         |> reload()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Não foi possível sincronizar o Caixa")}
    end
  end

  defp reload(socket) do
    rows = CashFlow.list_rows()

    assign(socket,
      rows: rows,
      current_row: Enum.find(rows, & &1.current)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="cash-flow" pending={@pending}>
      <div class="page-heading cash-flow-heading">
        <div>
          <p class="eyebrow">Panorama financeiro · ciclos do dia 5 ao dia 4</p>
          <h1>Visão mensal</h1>
          <p>Evolução global mês a mês: resultados, posição de caixa e investimentos.</p>
        </div>
        <div class="heading-actions cash-flow-heading-actions">
          <div class="cash-flow-period-chip">
            <span>Mês em aberto</span>
            <strong>{month_label(@current_start)}</strong>
          </div>
          <button
            type="button"
            id="sync-cash"
            phx-click="sync_cash"
            class="primary-action"
            title="Registrar Disponível e Obrigações da página Caixa"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" /> Sincronizar Caixa
          </button>
        </div>
      </div>

      <section class="cash-flow-hero monthly-summary">
        <div class="cash-flow-hero-metrics">
          <div>
            <span>EBIDA</span>
            <strong class={sign_class(@current_row.operational_result)}>
              {Format.money(@current_row.operational_result)}
            </strong>
            <small>Entradas − despesas</small>
          </div>
          <div>
            <span>Lucro</span>
            <strong class={sign_class(@current_row.profit)}>
              {Format.money(@current_row.profit)}
            </strong>
            <small>EBIDA + proventos</small>
          </div>
          <div>
            <span>Saldo líquido</span>
            <strong class={sign_class(@current_row.net_cash)}>
              {optional_money(@current_row.net_cash)}
            </strong>
            <small>Disponível + obrigações</small>
          </div>
          <div>
            <span>FCO ajustado</span>
            <strong
              id="current-free-cash-flow"
              class={sign_class(@current_row.free_cash_flow)}
            >
              {optional_money(@current_row.free_cash_flow)}
            </strong>
            <small>Δ Caixa liq. + Capex − juros/proventos</small>
          </div>
        </div>
      </section>

      <section class="cash-flow-history">
        <div class="cash-flow-history-heading">
          <div>
            <strong>Evolução mês a mês</strong>
            <span>
              Clique nas células pontilhadas para lançar Juros + proventos ou Capex. Enter salva; Esc cancela.
            </span>
          </div>
          <span>{month_count_label(@rows)}</span>
        </div>
        <div class="cash-flow-table-scroll">
          <table class="cash-flow-table">
            <colgroup>
              <col class="month-column" />
              <col :for={_index <- 1..11} />
            </colgroup>
            <thead>
              <tr>
                <th>Mês</th>
                <th>Entradas</th>
                <th>Despesas</th>
                <th title="Entradas menos despesas">EBIDA</th>
                <th>Juros + prov.</th>
                <th title="EBIDA mais juros e proventos">Lucro</th>
                <th>Disponível</th>
                <th>Obrigações</th>
                <th title="Disponível mais obrigações">Saldo líquido</th>
                <th title="Saldo líquido atual menos o saldo líquido anterior">Δ Caixa liq.</th>
                <th>Capex</th>
                <th title="Δ Caixa líquido + Capex − Juros e proventos">FCO ajust.</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={"cash-flow-row-#{row.period_start}"}
                class={row.current && "current"}
              >
                <td class="cash-flow-month-cell">
                  <div title={row.opening && "Saldo inicial"}>
                    <strong>{short_month_label(row.period_start)}</strong>
                    <small :if={row.current}>aberto</small>
                    <small :if={row.opening} class="opening">início</small>
                  </div>
                </td>
                <.money_cell value={unless(row.opening, do: row.income)} optional={row.opening} />
                <.money_cell value={unless(row.opening, do: row.expenses)} optional={row.opening} />
                <.money_cell
                  value={unless(row.opening, do: row.operational_result)}
                  optional={row.opening}
                  signed
                  tinted={!row.opening}
                />
                <%= if row.opening do %>
                  <.money_cell optional />
                <% else %>
                  <.editable_money_cell
                    row={row}
                    field="investment_income"
                    value={row.investment_income}
                    editing={@editing}
                    cell_value={@cell_value}
                    cell_preview={@cell_preview}
                    cell_error={@cell_error}
                  />
                <% end %>
                <.money_cell
                  value={unless(row.opening, do: row.profit)}
                  optional={row.opening}
                  signed
                  tinted={!row.opening}
                />
                <.money_cell value={row.available} optional />
                <.money_cell value={row.obligations} optional signed />
                <.money_cell value={row.net_cash} optional signed />
                <.money_cell
                  value={row.net_cash_change}
                  optional
                  signed
                  tinted={!row.opening}
                />
                <%= if row.opening do %>
                  <.money_cell optional />
                <% else %>
                  <.editable_money_cell
                    row={row}
                    field="capex"
                    value={row.capex}
                    editing={@editing}
                    cell_value={@cell_value}
                    cell_preview={@cell_preview}
                    cell_error={@cell_error}
                    signed
                  />
                <% end %>
                <.money_cell
                  value={row.free_cash_flow}
                  optional
                  signed
                  tinted={!row.opening}
                />
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusCell">
        export default {
          mounted() {
            this.el.focus()
            this.el.select()
          }
        }
      </script>
    </Layouts.app>
    """
  end

  attr :value, :integer, default: nil
  attr :optional, :boolean, default: false
  attr :signed, :boolean, default: false
  attr :tinted, :boolean, default: false

  defp money_cell(assigns) do
    ~H"""
    <td class={[
      "money-cell",
      @signed && sign_class(@value),
      @tinted && "tinted",
      is_nil(@value) && "missing"
    ]}>
      {if @optional, do: optional_money(@value), else: Format.money(@value || 0)}
    </td>
    """
  end

  attr :row, :map, required: true
  attr :field, :string, required: true
  attr :value, :integer, required: true
  attr :editing, :any, required: true
  attr :cell_value, :string, required: true
  attr :cell_preview, :integer, default: nil
  attr :cell_error, :string, default: nil
  attr :signed, :boolean, default: false

  defp editable_money_cell(assigns) do
    assigns =
      assign(assigns, :active, assigns.editing == {assigns.row.period_start, assigns.field})

    ~H"""
    <td class={[
      "money-cell editable-money-cell",
      @signed && sign_class(@value),
      @active && "editing"
    ]}>
      <%= if @active do %>
        <form
          id={"cell-editor-#{@field}-#{@row.period_start}"}
          phx-change="preview_cell"
          phx-submit="save_cell"
          phx-click-away="cancel_edit"
          phx-window-keydown="cancel_edit"
          phx-key="Escape"
          class="cell-editor"
        >
          <input type="hidden" name="period" value={@row.period_start} />
          <input type="hidden" name="field" value={@field} />
          <input
            id={"cell-input-#{@field}-#{@row.period_start}"}
            name="value"
            value={@cell_value}
            autocomplete="off"
            inputmode="decimal"
            phx-debounce="120"
            phx-hook=".FocusCell"
            aria-label={"Editar #{field_label(@field)} de #{month_label(@row.period_start)}"}
          />
          <small class={@cell_error && "error"} title={@cell_error}>
            {cell_helper(@cell_preview, @cell_error)}
          </small>
        </form>
      <% else %>
        <button
          type="button"
          phx-click="edit_cell"
          phx-value-period={@row.period_start}
          phx-value-field={@field}
          title={"Editar #{field_label(@field)} · aceita somas como 2+440+59"}
          aria-label={"Editar #{field_label(@field)} de #{month_label(@row.period_start)}"}
        >
          {Format.money(@value)}
        </button>
      <% end %>
    </td>
    """
  end

  defp expression_value(period_start, "investment_income") do
    case CashFlow.get_month(period_start) do
      nil -> ""
      month -> month.investment_income_expression
    end
  end

  defp expression_value(period_start, "capex") do
    case CashFlow.get_month(period_start) do
      nil -> ""
      month -> month.capex_expression
    end
  end

  defp expression_attrs("investment_income", value), do: %{investment_income_expression: value}
  defp expression_attrs("capex", value), do: %{capex_expression: value}

  defp parse_preview(value) do
    case SumExpression.parse(value) do
      {:ok, cents} -> cents
      :error -> nil
    end
  end

  defp cell_helper(_preview, error) when is_binary(error), do: "inválido"
  defp cell_helper(preview, nil) when is_integer(preview), do: "= #{Format.money(preview)}"
  defp cell_helper(_preview, _error), do: "Digite uma soma"

  defp field_label("investment_income"), do: "Juros + proventos"
  defp field_label("capex"), do: "Capex"

  defp sign_class(value) when is_integer(value) and value > 0, do: "positive"
  defp sign_class(value) when is_integer(value) and value < 0, do: "negative"
  defp sign_class(_value), do: "neutral"

  defp optional_money(value) when is_integer(value), do: Format.money(value)
  defp optional_money(_value), do: "—"

  defp month_label(%Date{month: month, year: year}),
    do: "#{Enum.at(@month_names, month - 1)} #{year}"

  defp short_month_label(%Date{month: month, year: year}) do
    short_month = @month_names |> Enum.at(month - 1) |> String.slice(0, 3) |> String.upcase()
    "#{short_month} #{String.slice(to_string(year), 2, 2)}"
  end

  defp month_count_label([_row]), do: "1 mês"
  defp month_count_label(rows), do: "#{length(rows)} meses"
end
