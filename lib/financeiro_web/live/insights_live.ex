defmodule FinanceiroWeb.InsightsLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias Financeiro.MonthPeriod
  alias FinanceiroWeb.Format

  @month_names ~w(Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro)

  @impl true
  def mount(_params, _session, socket) do
    today = MonthPeriod.current_date()
    period_starts = Ledger.spending_periods(today)
    current_start = MonthPeriod.period_start(today)
    comparison = comparison_rows(period_starts, today)
    selected_categories = comparison.categories |> Enum.map(& &1.label) |> MapSet.new()

    {:ok,
     socket
     |> assign(
       page_title: "Análises",
       today: today,
       period_starts: period_starts,
       comparison: comparison,
       selected_comparison_categories: selected_categories,
       comparison_chart: comparison_chart(comparison, selected_categories),
       section: "month"
     )
     |> load_period(current_start)}
  end

  @impl true
  def handle_event("section", %{"section" => section}, socket)
      when section in ["month", "comparison"],
      do: {:noreply, assign(socket, section: section)}

  def handle_event("select_period", %{"period" => period}, socket) do
    with {:ok, period_start} <- Date.from_iso8601(period),
         true <- period_start in socket.assigns.period_starts do
      {:noreply, load_period(socket, period_start)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_comparison_category", %{"category" => category}, socket) do
    available_categories = Enum.map(socket.assigns.comparison.categories, & &1.label)

    if category in available_categories do
      selected = socket.assigns.selected_comparison_categories

      selected =
        if MapSet.member?(selected, category),
          do: MapSet.delete(selected, category),
          else: MapSet.put(selected, category)

      {:noreply, assign_comparison_categories(socket, selected)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_all_comparison_categories", _params, socket) do
    selected = socket.assigns.comparison.categories |> Enum.map(& &1.label) |> MapSet.new()
    {:noreply, assign_comparison_categories(socket, selected)}
  end

  def handle_event("clear_comparison_categories", _params, socket) do
    {:noreply, assign_comparison_categories(socket, MapSet.new())}
  end

  defp assign_comparison_categories(socket, selected) do
    assign(socket,
      selected_comparison_categories: selected,
      comparison_chart: comparison_chart(socket.assigns.comparison, selected)
    )
  end

  defp load_period(socket, period_start) do
    period_end = MonthPeriod.period_end(period_start)
    filters = %{"from" => Date.to_iso8601(period_start), "to" => Date.to_iso8601(period_end)}
    totals = Ledger.totals(filters)

    assign(socket,
      selected_start: period_start,
      totals: totals,
      pending: totals.pending,
      owners: Ledger.spending_by(:owner, period_start, period_end),
      banks: Ledger.spending_by(:bank, period_start, period_end),
      forecast: monthly_forecast(period_start, socket.assigns.today)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="insights" pending={@pending}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">Laboratório visual</p>
          <h1>Análises</h1>
          <p>
            <%= if @section == "month" do %>
              Mês financeiro de {Format.short_date(@forecast.period_start)} a {Format.short_date(
                @forecast.period_end
              )}.
            <% else %>
              Compare a evolução de todos os meses financeiros.
            <% end %>
          </p>
        </div>
        <div class="view-switcher" role="tablist" aria-label="Visualização das análises">
          <button
            role="tab"
            aria-selected={to_string(@section == "month")}
            phx-click="section"
            phx-value-section="month"
            class={@section == "month" && "active"}
          >
            Por mês
          </button>
          <button
            role="tab"
            aria-selected={to_string(@section == "comparison")}
            phx-click="section"
            phx-value-section="comparison"
            class={@section == "comparison" && "active"}
          >
            Comparar meses
          </button>
        </div>
      </div>

      <div :if={@section == "month"} class="insight-toolbar">
        <form id="insights-period-form" phx-change="select_period">
          <label>
            <span>Mês analisado</span>
            <select name="period" aria-label="Selecionar mês da análise">
              <option
                :for={period_start <- @period_starts}
                value={period_start}
                selected={period_start == @selected_start}
              >
                {month_label(period_start)}
              </option>
            </select>
          </label>
        </form>
      </div>

      <section :if={@section == "month"} class="insight-view panorama-view">
        <div class="forecast-hero">
          <div>
            <span>{if @forecast.current, do: "Realizado até hoje", else: "Total do período"}</span>
            <strong id="forecast-actual">{Format.money(@forecast.actual_total)}</strong>
            <small>
              <%= if @forecast.current do %>
                gasto líquido em {@forecast.elapsed_days} dias do ciclo · estornos já descontados
              <% else %>
                ciclo encerrado · despesas líquidas com estornos já descontados
              <% end %>
            </small>
          </div>
          <div class="forecast-metrics">
            <div>
              <%= if @forecast.current do %>
                <span>Projeção até {Format.short_date(@forecast.period_end)}</span><strong id="forecast-total">{Format.money(
                    @forecast.projected_total
                  )}</strong>
              <% else %>
                <span>Maior categoria</span><strong id="forecast-total">{@forecast.top_category}</strong>
              <% end %>
            </div>
            <div>
              <span>Média por dia</span><strong>{Format.money(@forecast.daily_average)}</strong>
            </div>
            <div>
              <span>{if @forecast.current, do: "Dias restantes", else: "Lançamentos"}</span><strong>{if @forecast.current,
                  do: @forecast.remaining_days,
                  else: @totals.count}</strong>
            </div>
          </div>
        </div>

        <div class="insight-grid">
          <article class="insight-card forecast-card category-ranking">
            <div class="card-title">
              <div>
                <span>01</span>
                <h2>
                  {if @forecast.current, do: "Realizado e projeção", else: "Gastos por categoria"}
                </h2>
              </div>
              <div :if={@forecast.current} class="forecast-legend">
                <small><i class="actual"></i> realizado</small>
                <small><i class="projected"></i> projeção</small>
              </div>
            </div>

            <div class="forecast-list">
              <div
                :for={item <- @forecast.categories}
                class="forecast-row"
                data-category={item.category}
                style={category_style(item.category)}
              >
                <div class="forecast-category">
                  <i></i><strong>{item.category}</strong>
                </div>
                <div class="forecast-values">
                  <strong>{Format.money(item.actual)}</strong>
                  <span :if={@forecast.current}>proj. {Format.money(item.projected)}</span>
                </div>
                <div class="forecast-track">
                  <i
                    :if={@forecast.current}
                    class="projected"
                    style={"width: #{percent(max(item.projected, 0), @forecast.max_projected)}%"}
                  >
                  </i>
                  <i
                    class="actual"
                    style={"width: #{percent(max(item.actual, 0), @forecast.max_projected)}%"}
                  >
                  </i>
                </div>
              </div>
            </div>

            <p class="forecast-note">
              <%= if @forecast.current do %>
                Estimativa linear: gasto líquido acumulado ÷ dias corridos × dias do ciclo. Estornos reduzem o realizado e a projeção.
              <% else %>
                Valores finais do ciclo financeiro selecionado. Estornos já reduzem cada categoria.
              <% end %>
            </p>
          </article>
          <article class="insight-card split-card">
            <div class="card-title">
              <div>
                <span>02</span>
                <h2>Quem gastou</h2>
              </div>
              <small>por pessoa</small>
            </div>
            <div :for={{owner, value} <- @owners} class="person-total">
              <i>{initials(owner)}</i>
              <div>
                <strong>{owner}</strong><span>{Format.money(value)} · {percent(value, @totals.expenses)}%</span>
              </div>
            </div>
            <div class="stacked-bar">
              <i
                :for={{{_owner, value}, index} <- Enum.with_index(@owners)}
                style={"width: #{percent(value, @totals.expenses)}%; --index: #{index}"}
              >
              </i>
            </div>
          </article>
          <article class="insight-card bank-card">
            <div class="card-title">
              <div>
                <span>03</span>
                <h2>Por instituição</h2>
              </div>
            </div>
            <div :for={{bank, value} <- @banks} class="bank-row">
              <span>{bank}</span><strong>{Format.money(value)}</strong>
            </div>
          </article>
        </div>
      </section>

      <section :if={@section == "comparison"} class="insight-view comparison-view">
        <article class="insight-card month-total-overview">
          <div class="card-title">
            <div>
              <span>Resumo</span>
              <h2>Totais por mês</h2>
            </div>
            <small>visão rápida dos valores realizados</small>
          </div>
          <div class="month-total-list">
            <div
              :for={row <- @comparison.rows}
              id={"comparison-total-#{row.period_start}"}
              class={["month-total-item", row.current && "current"]}
            >
              <span>{month_label(row.period_start)}</span>
              <strong>{Format.money(row.expenses)}</strong>
              <small>{if row.current, do: "mês em andamento", else: "mês encerrado"}</small>
            </div>
          </div>
        </article>

        <div class="comparison-summary">
          <div>
            <span>Média mensal comparável</span><strong>{Format.money(@comparison.average)}</strong>
          </div>
          <div>
            <span>Maior mês</span><strong>{comparison_highlight(@comparison.highest)}</strong>
          </div>
          <div>
            <span>Tendência recente</span><strong class={delta_class(@comparison.recent_delta)}>
              {delta_label(@comparison.recent_delta)}
            </strong>
          </div>
          <div>
            <span>Categoria líder</span><strong>{category_highlight(
                @comparison.leading_category
              )}</strong>
          </div>
        </div>

        <article class="insight-card evolution-card">
          <div class="card-title">
            <div>
              <span>01</span>
              <h2>Gasto e composição por mês</h2>
            </div>
            <small>altura = gasto total · cores = categorias</small>
          </div>

          <div class="category-chart-filters" aria-label="Categorias exibidas no gráfico">
            <div class="category-filter-actions">
              <span>Exibir categorias</span>
              <button type="button" phx-click="select_all_comparison_categories">Todas</button>
              <button type="button" phx-click="clear_comparison_categories">Nenhuma</button>
            </div>
            <div class="category-filter-list">
              <button
                :for={item <- @comparison.categories}
                type="button"
                phx-click="toggle_comparison_category"
                phx-value-category={item.label}
                aria-pressed={to_string(MapSet.member?(@selected_comparison_categories, item.label))}
                class={!MapSet.member?(@selected_comparison_categories, item.label) && "inactive"}
                style={category_style(item.label)}
              >
                <i></i>{item.label}
              </button>
            </div>
          </div>

          <div
            class="monthly-evolution-chart"
            style={"--month-count: #{length(@comparison_chart.months)}"}
          >
            <div
              :for={row <- @comparison_chart.months}
              id={"comparison-month-#{row.period_start}"}
              class={["monthly-evolution-column", row.current && "current"]}
            >
              <div class="month-value">
                <strong>{Format.money(row.selected_expenses)}</strong>
                <span class={delta_class(row.selected_delta)}>{delta_label(row.selected_delta)}</span>
              </div>
              <div class="month-bar-area">
                <div
                  class="month-category-stack"
                  style={"height: #{percent(row.selected_expenses, @comparison_chart.max_expenses)}%"}
                >
                  <i
                    :for={segment <- row.selected_segments}
                    style={"flex: #{segment.value}; #{category_style(segment.category)}"}
                    title={"#{segment.category} · #{Format.money(segment.value)}"}
                  >
                  </i>
                </div>
              </div>
              <strong>{short_month_label(row.period_start)}</strong>
              <small :if={row.current}>
                projeção das categorias selecionadas
              </small>
              <small :if={!row.current}>ciclo encerrado</small>
            </div>
          </div>
          <p :if={MapSet.size(@selected_comparison_categories) == 0} class="chart-empty-note">
            Selecione ao menos uma categoria para preencher o gráfico.
          </p>
        </article>

        <section class="category-evolution-section">
          <div class="section-title">
            <h2>Como cada categoria está evoluindo</h2>
            <span>média mensal · valores realizados em ordem cronológica</span>
          </div>
          <div class="category-trend-grid">
            <article
              :for={item <- @comparison.categories}
              class="category-trend-card"
              data-category={item.label}
              style={category_style(item.label)}
            >
              <header>
                <div><i></i><strong>{item.label}</strong></div>
                <span class={delta_class(item.actual_recent_delta)}>
                  {delta_label(item.actual_recent_delta)}
                </span>
              </header>
              <div class="category-trend-value">
                <span>Média mensal</span>
                <strong>{Format.money(item.actual_average)}</strong>
                <small>Mês atual · {Format.money(item.latest_actual)}</small>
              </div>
              <svg viewBox="0 0 180 52" role="img" aria-label={"Evolução de #{item.label}"}>
                <line x1="0" y1="48" x2="180" y2="48"></line>
                <polyline points={item.actual_sparkline}></polyline>
              </svg>
              <footer>
                <span>Total <strong>{Format.money(item.actual_total)}</strong></span>
                <span>
                  Pico
                  <strong>
                    {short_month_label(item.actual_peak_period)} · {Format.money(
                      item.actual_peak_value
                    )}
                  </strong>
                </span>
              </footer>
            </article>
          </div>
        </section>

        <article id="category-heatmap" class="insight-card category-heatmap-card">
          <div class="card-title">
            <div>
              <span>02</span>
              <h2>Mapa de evolução das categorias</h2>
            </div>
            <small>mais cor = maior gasto dentro da própria categoria</small>
          </div>
          <div class="category-heatmap-wrap">
            <table class="category-heatmap">
              <thead>
                <tr>
                  <th>Categoria</th>
                  <th :for={row <- @comparison.months}>
                    {short_month_label(row.period_start)}<em :if={row.current}>*</em>
                  </th>
                  <th>Média</th>
                  <th>Última variação</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @comparison.categories} data-category={item.label}>
                  <td style={category_style(item.label)}><i></i><strong>{item.label}</strong></td>
                  <td
                    :for={value <- item.chronological_values}
                    style={heatmap_style(item.label, value, item.max_value)}
                    title={Format.money(value)}
                  >
                    {Format.money(value)}
                  </td>
                  <td>{Format.money(item.average)}</td>
                  <td class={delta_class(item.recent_delta)}>{delta_label(item.recent_delta)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@comparison.latest.current} class="comparison-current-note">
            * mês em andamento: projeção baseada no ritmo atual. O valor realizado aparece nos cartões acima.
          </p>
        </article>
      </section>
    </Layouts.app>
    """
  end

  defp monthly_forecast(period_start, today) do
    period_end = MonthPeriod.period_end(period_start)
    current = period_start == MonthPeriod.period_start(today)
    through_date = if current, do: today, else: period_end
    elapsed_days = Date.diff(through_date, period_start) + 1
    days_in_period = Date.diff(period_end, period_start) + 1

    actual_by_category =
      period_start
      |> Ledger.spending_by_category_between(through_date)
      |> Map.new()

    categories =
      Ledger.categories()
      |> Enum.map(fn category ->
        actual = Map.get(actual_by_category, category, 0)

        %{
          category: category,
          actual: actual,
          projected: if(current, do: round(actual * days_in_period / elapsed_days), else: actual)
        }
      end)
      |> Enum.sort_by(&{-&1.projected, &1.category})

    actual_total = Enum.sum(Enum.map(categories, & &1.actual))

    projected_total =
      if current, do: round(actual_total * days_in_period / elapsed_days), else: actual_total

    %{
      current: current,
      categories: categories,
      actual_total: actual_total,
      projected_total: projected_total,
      daily_average: round(actual_total / elapsed_days),
      elapsed_days: elapsed_days,
      period_days: days_in_period,
      remaining_days: if(current, do: days_in_period - elapsed_days, else: 0),
      period_start: period_start,
      period_end: period_end,
      top_category:
        categories
        |> Enum.find(&(&1.actual > 0))
        |> then(&if(&1, do: &1.category, else: "Sem despesas")),
      max_projected:
        categories |> Enum.map(&max(&1.projected, 0)) |> Enum.max(fn -> 1 end) |> max(1)
    }
  end

  defp comparison_rows(period_starts, today) do
    current_start = MonthPeriod.period_start(today)

    rows =
      period_starts
      |> Ledger.spending_period_summaries()
      |> Enum.sort_by(& &1.period_start, Date)
      |> Enum.map_reduce(nil, fn row, previous_expenses ->
        current = row.period_start == current_start
        through_date = if current, do: today, else: row.period_end
        days = Date.diff(through_date, row.period_start) + 1
        period_days = Date.diff(row.period_end, row.period_start) + 1

        analysis_expenses =
          if current, do: round(row.expenses * period_days / days), else: row.expenses

        comparison_category_totals =
          Map.new(row.category_totals, fn {category, value} ->
            {category, if(current, do: round(value * period_days / days), else: value)}
          end)

        delta = percentage_change(analysis_expenses, previous_expenses)
        segments = category_segments(comparison_category_totals)

        {Map.merge(row, %{
           current: current,
           delta: delta,
           analysis_expenses: analysis_expenses,
           comparison_category_totals: comparison_category_totals,
           segments: segments
         }), analysis_expenses}
      end)
      |> elem(0)
      |> Enum.reverse()

    expenses = Enum.map(rows, & &1.analysis_expenses)
    categories = breakdown_rows(rows, :comparison_category_totals)
    latest = List.first(rows)

    %{
      rows: rows,
      months: Enum.reverse(rows),
      latest: latest,
      average: safe_div(Enum.sum(expenses), length(expenses)),
      highest: Enum.max_by(rows, & &1.analysis_expenses, fn -> nil end),
      recent_delta: latest && latest.delta,
      leading_category:
        categories
        |> Enum.filter(&(&1.latest > 0))
        |> Enum.max_by(& &1.latest, fn -> nil end),
      max_expenses: Enum.max(expenses, fn -> 1 end) |> max(1),
      categories: categories
    }
  end

  defp comparison_chart(comparison, selected_categories) do
    months =
      comparison.months
      |> Enum.map_reduce(nil, fn row, previous_expenses ->
        selected_segments =
          Enum.filter(row.segments, &MapSet.member?(selected_categories, &1.category))

        selected_expenses = Enum.sum(Enum.map(selected_segments, & &1.value))

        {Map.merge(row, %{
           selected_segments: selected_segments,
           selected_expenses: selected_expenses,
           selected_delta: percentage_change(selected_expenses, previous_expenses)
         }), selected_expenses}
      end)
      |> elem(0)

    %{
      months: months,
      max_expenses: months |> Enum.map(& &1.selected_expenses) |> Enum.max(fn -> 1 end) |> max(1)
    }
  end

  defp category_segments(category_totals) do
    category_totals
    |> Enum.filter(fn {_category, value} -> value > 0 end)
    |> Enum.sort_by(fn {category, value} -> {-value, category} end)
    |> Enum.map(fn {category, value} -> %{category: category, value: value} end)
  end

  defp breakdown_rows(rows, field) do
    labels =
      rows
      |> Enum.flat_map(&(Map.fetch!(&1, field) |> Map.keys()))
      |> Enum.uniq()

    labels
    |> Enum.map(fn label ->
      values = Enum.map(rows, &(Map.fetch!(&1, field) |> Map.get(label, 0)))
      actual_values = Enum.map(rows, &(Map.fetch!(&1, :category_totals) |> Map.get(label, 0)))
      {peak_row, peak_value} = Enum.zip(rows, values) |> Enum.max_by(&elem(&1, 1))

      {actual_peak_row, actual_peak_value} =
        Enum.zip(rows, actual_values) |> Enum.max_by(&elem(&1, 1))

      chronological_values = Enum.reverse(values)
      actual_chronological_values = Enum.reverse(actual_values)

      %{
        label: label,
        values: values,
        chronological_values: chronological_values,
        latest: Enum.at(values, 0),
        latest_actual: Enum.at(actual_values, 0),
        actual_total: Enum.sum(actual_values),
        actual_average: safe_div(Enum.sum(actual_values), length(actual_values)),
        actual_recent_delta:
          percentage_change(Enum.at(actual_values, 0), Enum.at(actual_values, 1)),
        actual_peak_period: actual_peak_row.period_start,
        actual_peak_value: actual_peak_value,
        actual_sparkline: sparkline_points(actual_chronological_values),
        total: Enum.sum(values),
        average: safe_div(Enum.sum(values), length(values)),
        recent_delta: percentage_change(Enum.at(values, 0), Enum.at(values, 1)),
        peak_period: peak_row.period_start,
        peak_value: peak_value,
        max_value: Enum.max(values, fn -> 1 end) |> max(1),
        sparkline: sparkline_points(chronological_values)
      }
    end)
    |> Enum.sort_by(&{-abs(&1.total), &1.label})
  end

  defp percentage_change(_current, nil), do: nil
  defp percentage_change(0, 0), do: 0
  defp percentage_change(_current, 0), do: :new
  defp percentage_change(current, previous), do: round((current - previous) * 100 / previous)

  defp delta_label(nil), do: "—"
  defp delta_label(:new), do: "Novo"
  defp delta_label(delta) when delta > 0, do: "+#{delta}%"
  defp delta_label(delta), do: "#{delta}%"

  defp delta_class(delta) when is_integer(delta) and delta > 0, do: "comparison-delta up"
  defp delta_class(delta) when is_integer(delta) and delta < 0, do: "comparison-delta down"
  defp delta_class(_delta), do: "comparison-delta"

  defp comparison_highlight(nil), do: "Sem dados"

  defp comparison_highlight(row),
    do: "#{short_month_label(row.period_start)} · #{Format.money(row.analysis_expenses)}"

  defp category_highlight(nil), do: "Sem dados"
  defp category_highlight(item), do: "#{item.label} · #{Format.money(item.latest)}"

  defp sparkline_points(values) do
    max_value = Enum.max(values, fn -> 1 end) |> max(1)
    denominator = max(length(values) - 1, 1)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, index} ->
      x = round(index * 180 / denominator)
      y = 48 - round(max(value, 0) * 42 / max_value)
      "#{x},#{y}"
    end)
  end

  defp heatmap_style(category, value, max_value) do
    intensity = 12 + round(max(value, 0) * 72 / max(max_value, 1))

    "#{category_style(category)}; background: color-mix(in srgb, var(--category-color) #{intensity}%, white)"
  end

  defp month_label(%Date{month: month, year: year}),
    do: "#{Enum.at(@month_names, month - 1)} #{year}"

  defp short_month_label(%Date{month: month, year: year}) do
    @month_names |> Enum.at(month - 1) |> String.slice(0, 3) |> then(&"#{&1}/#{year}")
  end

  defp percent(_value, 0), do: 0
  defp percent(value, total), do: round(value * 100 / total)
  defp safe_div(_value, 0), do: 0
  defp safe_div(value, divisor), do: div(value, divisor)

  defp category_style(category) do
    {color, ink} = category_color(category)
    "--category-color: #{color}; --category-ink: #{ink}"
  end

  defp category_color("Casa"), do: {"#2563EB", "#FFFFFF"}
  defp category_color("Funcionarios"), do: {"#7C3AED", "#FFFFFF"}
  defp category_color("Mercado"), do: {"#16A34A", "#FFFFFF"}
  defp category_color("Restaurante"), do: {"#EA580C", "#FFFFFF"}
  defp category_color("Transporte"), do: {"#0891B2", "#FFFFFF"}
  defp category_color("Saude"), do: {"#DC2626", "#FFFFFF"}
  defp category_color("Extras"), do: {"#D946EF", "#FFFFFF"}
  defp category_color("Filho"), do: {"#EAB308", "#28200A"}
  defp category_color("Viagem"), do: {"#0D9488", "#FFFFFF"}
  defp category_color("Pet"), do: {"#92400E", "#FFFFFF"}
  defp category_color("Projetos"), do: {"#4F46E5", "#FFFFFF"}
  defp category_color(_), do: {"#64748B", "#FFFFFF"}

  defp initials(name) do
    name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1) |> String.upcase()
  end
end
