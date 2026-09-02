defmodule FinanceiroWeb.BudgetsLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Budgets
  alias Financeiro.Ledger
  alias Financeiro.MoneyInput
  alias FinanceiroWeb.Format

  @month_names ~w(Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Orçamentos",
       pending: Ledger.pending_count(),
       editing: nil,
       budget_value: "",
       budget_error: nil
     )
     |> reload()}
  end

  @impl true
  def handle_event("edit_budget", %{"period" => period}, socket) do
    with {:ok, period_start} <- Date.from_iso8601(period),
         row when not is_nil(row) <-
           Enum.find(socket.assigns.rows, &(&1.period_start == period_start)) do
      {:noreply,
       assign(socket,
         editing: period_start,
         budget_value: MoneyInput.format(row.budget),
         budget_error: nil
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_budget", _params, socket), do: {:noreply, socket}

  def handle_event("validate_budget", %{"period" => period, "value" => value}, socket) do
    case {Date.from_iso8601(period), MoneyInput.parse(value)} do
      {{:ok, period_start}, {:ok, cents}} when cents >= 0 ->
        {:noreply, assign(socket, editing: period_start, budget_value: value, budget_error: nil)}

      {{:ok, period_start}, _} ->
        {:noreply,
         assign(socket,
           editing: period_start,
           budget_value: value,
           budget_error: "Informe um valor igual ou maior que zero"
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("validate_budget", _params, socket), do: {:noreply, socket}

  def handle_event("save_budget", %{"period" => period, "value" => value}, socket) do
    with {:ok, period_start} <- Date.from_iso8601(period),
         {:ok, _month} <- Budgets.set_budget(period_start, value) do
      {:noreply,
       socket
       |> assign(editing: nil, budget_value: "", budget_error: nil)
       |> put_flash(:info, "Orçamento de #{month_label(period_start)} atualizado")
       |> reload()}
    else
      _ ->
        {:noreply,
         assign(socket,
           budget_value: value,
           budget_error: "Informe um valor igual ou maior que zero"
         )}
    end
  end

  def handle_event("save_budget", _params, socket), do: {:noreply, socket}

  def handle_event("reset_budget", %{"period" => period}, socket) do
    with {:ok, period_start} <- Date.from_iso8601(period),
         {:ok, _month} <- Budgets.reset_budget(period_start) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Orçamento restaurado para #{Format.money(Budgets.default_monthly_budget_cents())}"
       )
       |> reload()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível restaurar o orçamento")}
    end
  end

  def handle_event("reset_budget", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing: nil, budget_value: "", budget_error: nil)}
  end

  defp reload(socket) do
    rows = Budgets.list_rows()
    assign(socket, rows: rows, current_row: Enum.find(rows, & &1.current))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="budgets" pending={@pending}>
      <div class="page-heading budget-heading">
        <div>
          <p class="eyebrow">Planejamento · ciclos do dia 5 ao dia 4</p>
          <h1>Orçamentos</h1>
          <p>Compare as despesas do mês com o limite mensal e com o saldo acumulado.</p>
        </div>
        <div class="budget-default-chip">
          <span>Orçamento padrão</span>
          <strong>{Format.money(Budgets.default_monthly_budget_cents())}</strong>
          <small>por mês</small>
        </div>
      </div>

      <section
        id="current-budget-summary"
        class={["budget-hero", @current_row.rollover_remaining < 0 && "exceeded"]}
      >
        <div class="budget-hero-main">
          <div class="budget-hero-label">
            <span>Saldo com acúmulo · {month_label(@current_row.period_start)}</span>
            <span class={["budget-status", status_class(@current_row.rollover_remaining)]}>
              {status_label(@current_row.rollover_remaining)}
            </span>
          </div>
          <strong class={sign_class(@current_row.rollover_remaining)}>
            {Format.money(@current_row.rollover_remaining)}
          </strong>
          <small>
            {rollover_explanation(@current_row.rollover_from_previous)}
          </small>
          <div
            class="budget-progress"
            aria-label={usage_label(@current_row.expenses, @current_row.rollover_budget)}
          >
            <i style={"width: #{progress_percent(@current_row.expenses, @current_row.rollover_budget)}%"}>
            </i>
          </div>
          <div class="budget-progress-labels">
            <span>{usage_label(@current_row.expenses, @current_row.rollover_budget)}</span>
            <span>
              {Format.money(@current_row.expenses)} de {Format.money(@current_row.rollover_budget)}
            </span>
          </div>
        </div>
        <div class="budget-hero-metrics">
          <div>
            <span>Despesas</span>
            <strong>{Format.money(@current_row.expenses)}</strong>
            <small>compras menos estornos</small>
          </div>
          <div>
            <span>Limite mensal</span>
            <strong>{Format.money(@current_row.budget)}</strong>
            <small>{if @current_row.custom_budget, do: "personalizado", else: "valor padrão"}</small>
          </div>
          <div>
            <span>Saldo só do mês</span>
            <strong class={sign_class(@current_row.monthly_remaining)}>
              {Format.money(@current_row.monthly_remaining)}
            </strong>
            <small>sem considerar meses anteriores</small>
          </div>
          <div>
            <span>Acumulado anterior</span>
            <strong class={sign_class(@current_row.rollover_from_previous)}>
              {Format.money(@current_row.rollover_from_previous)}
            </strong>
            <small>superávit ou estouro trazido</small>
          </div>
        </div>
      </section>

      <section class="budget-history">
        <div class="budget-history-heading">
          <div>
            <strong>Histórico mensal</strong>
            <span>
              Clique no orçamento para personalizar. O saldo com acúmulo vira o saldo anterior do mês seguinte.
            </span>
          </div>
          <span>{month_count_label(@rows)}</span>
        </div>
        <div class="budget-table-scroll">
          <table class="budget-table">
            <thead>
              <tr>
                <th>Mês</th>
                <th>Despesas</th>
                <th>Orçamento mensal</th>
                <th>Saldo mensal</th>
                <th>Acumulado anterior</th>
                <th>Limite com acúmulo</th>
                <th>Saldo com acúmulo</th>
                <th>Situação</th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={row <- @rows}
                id={"budget-row-#{row.period_start}"}
                class={[row.current && "current", row.future && "future"]}
              >
                <td class="budget-month-cell">
                  <div>
                    <strong>{short_month_label(row.period_start)}</strong>
                    <small :if={row.current}>aberto</small>
                    <small :if={row.future} class="future-label">futuro</small>
                  </div>
                  <span>
                    {Format.short_date(row.period_start)}–{Format.short_date(row.period_end)}
                  </span>
                </td>
                <td class="budget-money">{Format.money(row.expenses)}</td>
                <td class={[
                  "budget-money",
                  "budget-editable",
                  @editing == row.period_start && "editing"
                ]}>
                  <%= if @editing == row.period_start do %>
                    <form
                      id={"budget-editor-#{row.period_start}"}
                      phx-change="validate_budget"
                      phx-submit="save_budget"
                      phx-click-away="cancel_edit"
                      phx-window-keydown="cancel_edit"
                      phx-key="Escape"
                    >
                      <input type="hidden" name="period" value={row.period_start} />
                      <div>
                        <span>R$</span>
                        <input
                          id={"budget-input-#{row.period_start}"}
                          name="value"
                          value={@budget_value}
                          inputmode="decimal"
                          autocomplete="off"
                          phx-debounce="120"
                          phx-hook=".FocusBudget"
                          aria-label={"Orçamento de #{month_label(row.period_start)}"}
                        />
                      </div>
                      <small class={@budget_error && "error"}>
                        {if @budget_error, do: @budget_error, else: "Enter para salvar"}
                      </small>
                    </form>
                  <% else %>
                    <button
                      type="button"
                      phx-click="edit_budget"
                      phx-value-period={row.period_start}
                      aria-label={"Editar orçamento de #{month_label(row.period_start)}"}
                    >
                      <strong>{Format.money(row.budget)}</strong>
                      <small>{if row.custom_budget, do: "personalizado", else: "padrão"}</small>
                    </button>
                  <% end %>
                </td>
                <td class={["budget-money", sign_class(row.monthly_remaining)]}>
                  {Format.money(row.monthly_remaining)}
                </td>
                <td class={["budget-money", sign_class(row.rollover_from_previous)]}>
                  {Format.money(row.rollover_from_previous)}
                </td>
                <td class="budget-money">{Format.money(row.rollover_budget)}</td>
                <td class={["budget-money", "emphasis", sign_class(row.rollover_remaining)]}>
                  {Format.money(row.rollover_remaining)}
                </td>
                <td class="budget-status-cell">
                  <span class={["budget-status", status_class(row.rollover_remaining)]}>
                    {status_label(row.rollover_remaining)}
                  </span>
                  <button
                    :if={row.custom_budget}
                    type="button"
                    phx-click="reset_budget"
                    phx-value-period={row.period_start}
                    data-confirm="Restaurar o orçamento padrão deste mês?"
                    title="Restaurar orçamento padrão"
                    aria-label={"Restaurar orçamento padrão de #{month_label(row.period_start)}"}
                    class="budget-reset"
                  >
                    <.icon name="hero-arrow-uturn-left-mini" class="size-3" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusBudget">
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

  defp sign_class(value) when value < 0, do: "negative"
  defp sign_class(value) when value > 0, do: "positive"
  defp sign_class(_value), do: "neutral"

  defp status_class(value) when value < 0, do: "over"
  defp status_class(_value), do: "within"

  defp status_label(value) when value < 0, do: "Estourado"
  defp status_label(_value), do: "Dentro do limite"

  defp progress_percent(_expenses, budget) when budget <= 0, do: 100

  defp progress_percent(expenses, budget) do
    expenses
    |> Kernel.*(100)
    |> div(budget)
    |> max(0)
    |> min(100)
  end

  defp usage_label(_expenses, budget) when budget <= 0, do: "Sem limite disponível"

  defp usage_label(expenses, budget) do
    percent = expenses * 100 / budget
    "#{:erlang.float_to_binary(percent, decimals: 1)}% usado"
  end

  defp rollover_explanation(0),
    do: "Este é o primeiro mês do histórico; ainda não há saldo anterior."

  defp rollover_explanation(value) when value > 0,
    do: "Inclui #{Format.money(value)} que sobraram dos meses anteriores."

  defp rollover_explanation(value),
    do: "Desconta #{Format.money(abs(value))} excedidos nos meses anteriores."

  defp month_label(%Date{month: month, year: year}),
    do: "#{Enum.at(@month_names, month - 1)} #{year}"

  defp short_month_label(%Date{month: month, year: year}) do
    short_month = @month_names |> Enum.at(month - 1) |> String.slice(0, 3) |> String.upcase()
    "#{short_month} #{String.slice(to_string(year), 2, 2)}"
  end

  defp month_count_label([_row]), do: "1 mês"
  defp month_count_label(rows), do: "#{length(rows)} meses"
end
