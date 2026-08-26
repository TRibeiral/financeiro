defmodule FinanceiroWeb.InsightsLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias Financeiro.MonthPeriod
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    today = MonthPeriod.current_date()
    {period_start, period_end} = MonthPeriod.bounds(today)
    period_filters = MonthPeriod.filters(today)
    totals = Ledger.totals(period_filters)
    daily = daily_spending(period_start, period_end)
    forecast = monthly_forecast(today)

    {:ok,
     assign(socket,
       page_title: "Análises",
       pending: totals.pending,
       totals: totals,
       owners: Ledger.spending_by(:owner, period_start, period_end),
       banks: Ledger.spending_by(:bank, period_start, period_end),
       daily: daily,
       max_day_activity: max_day_activity(daily),
       forecast: forecast,
       mode: "panorama"
     )}
  end

  @impl true
  def handle_event("mode", %{"mode" => mode}, socket), do: {:noreply, assign(socket, mode: mode)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="insights" pending={@pending}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">Laboratório visual</p>
          <h1>Análises</h1>
          <p>
            Mês financeiro de {Format.short_date(@forecast.period_start)} a {Format.short_date(
              @forecast.period_end
            )}.
          </p>
        </div>
        <div class="view-switcher">
          <button
            :for={{key, label} <- [{"panorama", "Panorama"}, {"ritmo", "Ritmo"}]}
            phx-click="mode"
            phx-value-mode={key}
            class={@mode == key && "active"}
          >
            {label}
          </button>
        </div>
      </div>

      <section :if={@mode == "panorama"} class="insight-view panorama-view">
        <div class="forecast-hero">
          <div>
            <span>Realizado até hoje</span>
            <strong id="forecast-actual">{Format.money(@forecast.actual_total)}</strong>
            <small>
              gasto líquido em {@forecast.elapsed_days} dias do ciclo · estornos já descontados
            </small>
          </div>
          <div class="forecast-metrics">
            <div>
              <span>Projeção até {Format.short_date(@forecast.period_end)}</span><strong id="forecast-total">{Format.money(
                  @forecast.projected_total
                )}</strong>
            </div>
            <div>
              <span>Média por dia</span><strong>{Format.money(@forecast.daily_average)}</strong>
            </div>
            <div>
              <span>Dias restantes</span><strong>{@forecast.remaining_days}</strong>
            </div>
          </div>
        </div>

        <div class="insight-grid">
          <article class="insight-card forecast-card category-ranking">
            <div class="card-title">
              <div>
                <span>01</span>
                <h2>Realizado e projeção</h2>
              </div>
              <div class="forecast-legend">
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
                  <span>proj. {Format.money(item.projected)}</span>
                </div>
                <div class="forecast-track">
                  <i
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
              Estimativa linear: gasto líquido acumulado ÷ dias corridos × dias do ciclo. Estornos reduzem o realizado e a projeção.
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

      <section :if={@mode == "ritmo"} class="insight-view rhythm-view">
        <article class="insight-card timeline-card">
          <div class="card-title">
            <div>
              <span>01</span>
              <h2>Ritmo diário</h2>
            </div>
            <small>altura = volume do dia · cores = categorias</small>
          </div>
          <div class="daily-chart">
            <div
              :for={day <- @daily}
              class="day-column"
              title={"#{Format.date(day.date)} · líquido #{Format.money(day.total)}"}
            >
              <span>{Format.money(day.total)}</span>
              <div
                class="day-stack"
                style={"height: #{max(3, percent(day.activity, @max_day_activity))}%"}
              >
                <i
                  :for={segment <- day.segments}
                  class={segment.refund && "refund"}
                  data-category={segment.category}
                  style={
                    "--segment-weight: #{max(abs(segment.value), 1)}; #{category_style(segment.category)}"
                  }
                  title={"#{segment.category} · #{Format.money(segment.value)}"}
                >
                </i>
              </div>
              <small>{Format.short_date(day.date)}</small>
            </div>
          </div>
          <div class="rhythm-legend">
            <span
              :for={item <- @forecast.categories}
              style={category_style(item.category)}
            >
              <i></i>{item.category}
            </span>
            <span class="refund-key"><i></i> estorno</span>
          </div>
        </article>
        <div class="rhythm-notes">
          <div><span>Dias com movimento</span><strong>{length(@daily)}</strong></div>
          <div>
            <span>Média por dia ativo</span><strong>{Format.money(
                safe_div(@totals.expenses, length(@daily))
              )}</strong>
          </div>
          <div>
            <span>Maior dia</span><strong>{Format.date(largest_day(@daily))}</strong>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp monthly_forecast(today) do
    {period_start, period_end} = MonthPeriod.bounds(today)
    elapsed_days = Date.diff(today, period_start) + 1
    days_in_period = Date.diff(period_end, period_start) + 1

    actual_by_category =
      period_start
      |> Ledger.spending_by_category_between(today)
      |> Map.new()

    categories =
      Ledger.categories()
      |> Enum.map(fn category ->
        actual = Map.get(actual_by_category, category, 0)

        %{
          category: category,
          actual: actual,
          projected: round(actual * days_in_period / elapsed_days)
        }
      end)
      |> Enum.sort_by(&{-&1.projected, &1.category})

    actual_total = Enum.sum(Enum.map(categories, & &1.actual))
    projected_total = round(actual_total * days_in_period / elapsed_days)

    %{
      categories: categories,
      actual_total: actual_total,
      projected_total: projected_total,
      daily_average: round(actual_total / elapsed_days),
      elapsed_days: elapsed_days,
      period_days: days_in_period,
      remaining_days: days_in_period - elapsed_days,
      period_start: period_start,
      period_end: period_end,
      max_projected:
        categories |> Enum.map(&max(&1.projected, 0)) |> Enum.max(fn -> 1 end) |> max(1)
    }
  end

  defp daily_spending(period_start, period_end) do
    Ledger.spending_by_day_and_category(period_start, period_end)
    |> Enum.group_by(fn {date, _category, _flow_type, _value} -> date end)
    |> Enum.sort_by(&elem(&1, 0), Date)
    |> Enum.map(fn {date, entries} ->
      segments =
        entries
        |> Enum.map(fn {_date, category, flow_type, value} ->
          %{category: category, value: value, refund: flow_type == "refund"}
        end)
        |> Enum.sort_by(&{-abs(&1.value), &1.category})

      %{
        date: date,
        segments: segments,
        total: Enum.sum(Enum.map(segments, & &1.value)),
        activity: Enum.sum(Enum.map(segments, &abs(&1.value)))
      }
    end)
  end

  defp max_day_activity([]), do: 1

  defp max_day_activity(days) do
    days |> Enum.map(& &1.activity) |> Enum.max(fn -> 1 end) |> max(1)
  end

  defp largest_day([]), do: MonthPeriod.history_start()
  defp largest_day(days), do: days |> Enum.max_by(& &1.total) |> Map.fetch!(:date)

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
