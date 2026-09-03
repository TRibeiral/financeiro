defmodule FinanceiroWeb.SnapshotsLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Ledger
  alias Financeiro.Snapshots
  alias FinanceiroWeb.Format

  @chart_left 74
  @chart_right 930
  @chart_top 28
  @chart_bottom 220

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Patrimônio",
       pending: Ledger.pending_count(),
       expanded_id: nil
     )
     |> reload()}
  end

  @impl true
  def handle_event("sync", _params, socket) do
    case Snapshots.capture_current() do
      {:ok, _snapshot} ->
        {:noreply,
         socket
         |> put_flash(:info, "Snapshot do patrimônio salvo")
         |> reload()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Não foi possível salvar o snapshot")}
    end
  end

  def handle_event("toggle_details", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded_id = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, expanded_id: expanded_id)}
  end

  defp reload(socket) do
    snapshots = Snapshots.list_snapshots()
    latest = List.first(snapshots)
    previous = Enum.at(snapshots, 1)

    assign(socket,
      snapshots: snapshots,
      latest: latest,
      preview: Snapshots.current_preview(),
      latest_delta: delta(latest, previous),
      total_growth: delta(latest, List.last(snapshots)),
      history_rows: history_rows(snapshots),
      chart: chart_data(snapshots)
    )
  end

  defp history_rows(snapshots) do
    snapshots
    |> Enum.with_index()
    |> Enum.map(fn {snapshot, index} ->
      Map.put(snapshot, :change_cents, delta(snapshot, Enum.at(snapshots, index + 1)))
    end)
  end

  defp delta(nil, _other), do: nil
  defp delta(_snapshot, nil), do: nil
  defp delta(snapshot, other), do: snapshot.total_cents - other.total_cents

  defp chart_data([]), do: nil

  defp chart_data(snapshots) do
    snapshots = Enum.reverse(snapshots)
    totals = Enum.map(snapshots, & &1.total_cents)
    data_min = Enum.min(totals)
    data_max = Enum.max(totals)
    span = data_max - data_min
    padding = max(round(max(span * 0.12, abs(data_max) * 0.04)), 10_000)
    minimum = data_min - padding
    maximum = data_max + padding
    range = max(maximum - minimum, 1)
    count = length(snapshots)

    points =
      snapshots
      |> Enum.with_index()
      |> Enum.map(fn {snapshot, index} ->
        x =
          if count == 1,
            do: (@chart_left + @chart_right) / 2,
            else: @chart_left + index * (@chart_right - @chart_left) / (count - 1)

        y = @chart_top + (maximum - snapshot.total_cents) * (@chart_bottom - @chart_top) / range

        %{
          x: Float.round(x, 1),
          y: Float.round(y, 1),
          snapshot: snapshot,
          show_label: chart_label?(index, count)
        }
      end)

    point_string = Enum.map_join(points, " ", &"#{&1.x},#{&1.y}")
    first = List.first(points)
    last = List.last(points)

    %{
      points: points,
      point_string: point_string,
      area_path: "M #{first.x},#{@chart_bottom} L #{point_string} L #{last.x},#{@chart_bottom} Z",
      ticks:
        Enum.map(0..3, fn index ->
          ratio = index / 3

          %{
            y: Float.round(@chart_top + ratio * (@chart_bottom - @chart_top), 1),
            value: round(maximum - ratio * range)
          }
        end)
    }
  end

  defp chart_label?(index, count) when count <= 6, do: index < count

  defp chart_label?(index, count) do
    step = ceil((count - 1) / 5)
    index == 0 or index == count - 1 or rem(index, step) == 0
  end

  defp allocation_percent(_value, nil), do: 0

  defp allocation_percent(value, snapshot) do
    denominator =
      [snapshot.cash_cents, snapshot.stocks_cents, snapshot.other_investments_cents]
      |> Enum.filter(&(&1 > 0))
      |> Enum.sum()

    if value > 0 and denominator > 0, do: Float.round(value * 100 / denominator, 1), else: 0
  end

  defp percent_change(nil, _base), do: nil
  defp percent_change(_change, 0), do: nil
  defp percent_change(change, base), do: Float.round(change * 100 / abs(base), 1)

  defp signed_money(nil), do: "—"
  defp signed_money(0), do: Format.money(0)
  defp signed_money(value) when value > 0, do: "+#{Format.money(value)}"
  defp signed_money(value), do: Format.money(value)

  defp signed_percent(nil), do: nil
  defp signed_percent(value) when value > 0, do: "+#{format_decimal(value)}%"
  defp signed_percent(value), do: "#{format_decimal(value)}%"

  defp format_decimal(value) do
    value
    |> :erlang.float_to_binary(decimals: 1)
    |> String.replace(".", ",")
  end

  defp trend_class(nil), do: "neutral"
  defp trend_class(value) when value > 0, do: "positive"
  defp trend_class(value) when value < 0, do: "negative"
  defp trend_class(_value), do: "neutral"

  defp local_datetime(datetime), do: DateTime.add(datetime, -3, :hour)

  defp snapshot_datetime(datetime) do
    datetime = local_datetime(datetime)
    Calendar.strftime(datetime, "%d/%m/%Y às %H:%M")
  end

  defp chart_date(datetime) do
    datetime = local_datetime(datetime)
    Calendar.strftime(datetime, "%d/%m/%y")
  end

  defp category_items(snapshot, category),
    do: Enum.filter(snapshot.items, &(&1.category == category))

  defp category_total(snapshot, "cash"), do: snapshot.cash_cents
  defp category_total(snapshot, "stocks"), do: snapshot.stocks_cents

  defp category_total(snapshot, "other_investments"),
    do: snapshot.other_investments_cents

  defp item_caption(%{category: "stocks", shares: shares, quote_cents: quote_cents}) do
    quote = if quote_cents, do: Format.money(quote_cents), else: "sem cotação"
    "#{shares} ações × #{quote}"
  end

  defp item_caption(%{category: "cash", value_cents: value}) when value < 0,
    do: "Obrigação"

  defp item_caption(%{category: "cash"}), do: "Disponível"
  defp item_caption(_item), do: "Investimento"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="snapshots" pending={@pending}>
      <div class="page-heading snapshots-heading">
        <div>
          <p class="eyebrow">Evolução patrimonial</p>
          <h1>Patrimônio no tempo</h1>
          <p>Acompanhe como caixa e investimentos mudam a cada fotografia da carteira.</p>
        </div>
        <div class="snapshot-sync-wrap">
          <div class="snapshot-sync-preview">
            <span>Valor a registrar agora</span>
            <strong>{Format.money(@preview.total_cents)}</strong>
            <small>{@preview.item_count} posições nas 3 áreas</small>
          </div>
          <button
            id="sync-snapshot"
            type="button"
            class="primary-action snapshot-sync"
            phx-click="sync"
            phx-disable-with="Sincronizando…"
          >
            <.icon name="hero-arrow-path-mini" class="size-4" /> Sincronizar agora
          </button>
        </div>
      </div>

      <div :if={@preview.stocks_without_quote_count > 0} class="snapshot-warning" role="status">
        <.icon name="hero-exclamation-triangle-mini" class="size-4" />
        <span>
          {@preview.stocks_without_quote_count}
          {if @preview.stocks_without_quote_count == 1, do: "ação está", else: "ações estão"} sem cotação e {if @preview.stocks_without_quote_count ==
                                                                                                                  1,
                                                                                                                do:
                                                                                                                  "será registrada",
                                                                                                                else:
                                                                                                                  "serão registradas"} como R$ 0,00.
        </span>
        <.link navigate={~p"/stocks"}>Revisar ações</.link>
      </div>

      <%= if @latest do %>
        <section class="snapshot-hero">
          <div class="snapshot-total">
            <span>Patrimônio mais recente</span>
            <strong id="latest-net-worth">{Format.money(@latest.total_cents)}</strong>
            <div class={["snapshot-trend", trend_class(@latest_delta)]}>
              <.icon
                name={
                  if @latest_delta && @latest_delta < 0,
                    do: "hero-arrow-trending-down-mini",
                    else: "hero-arrow-trending-up-mini"
                }
                class="size-4"
              />
              <span>{signed_money(@latest_delta)}</span>
              <small :if={@latest_delta}>
                ({signed_percent(percent_change(@latest_delta, Enum.at(@snapshots, 1).total_cents))})
                desde o snapshot anterior
              </small>
              <small :if={!@latest_delta}>primeiro registro da série</small>
            </div>
          </div>
          <div class="snapshot-hero-side">
            <div>
              <span>Evolução total</span>
              <strong class={trend_class(@total_growth)}>{signed_money(@total_growth)}</strong>
              <small>desde o primeiro registro</small>
            </div>
            <div>
              <span>Última sincronização</span>
              <strong>{snapshot_datetime(@latest.captured_at)}</strong>
              <small>
                {@latest.cash_count + @latest.stocks_count + @latest.other_investments_count} posições preservadas
              </small>
            </div>
          </div>
        </section>

        <section class="snapshot-categories" aria-label="Composição do patrimônio">
          <article class="snapshot-category cash-category">
            <div class="snapshot-category-icon">
              <.icon name="hero-banknotes-mini" class="size-5" />
            </div>
            <div>
              <span>Caixa</span>
              <strong>{Format.money(@latest.cash_cents)}</strong>
              <small>
                {@latest.cash_count} {if @latest.cash_count == 1, do: "saldo", else: "saldos"}
              </small>
            </div>
            <div class="snapshot-category-share">
              <span>{allocation_percent(@latest.cash_cents, @latest)}%</span>
              <i style={"width: #{allocation_percent(@latest.cash_cents, @latest)}%"}></i>
            </div>
          </article>
          <article class="snapshot-category stocks-category">
            <div class="snapshot-category-icon">
              <.icon name="hero-presentation-chart-line-mini" class="size-5" />
            </div>
            <div>
              <span>Ações</span>
              <strong>{Format.money(@latest.stocks_cents)}</strong>
              <small>
                {@latest.stocks_count} {if @latest.stocks_count == 1, do: "posição", else: "posições"}
              </small>
            </div>
            <div class="snapshot-category-share">
              <span>{allocation_percent(@latest.stocks_cents, @latest)}%</span>
              <i style={"width: #{allocation_percent(@latest.stocks_cents, @latest)}%"}></i>
            </div>
          </article>
          <article class="snapshot-category other-category">
            <div class="snapshot-category-icon">
              <.icon name="hero-circle-stack-mini" class="size-5" />
            </div>
            <div>
              <span>Outros investimentos</span>
              <strong>{Format.money(@latest.other_investments_cents)}</strong>
              <small>
                {@latest.other_investments_count} {if @latest.other_investments_count == 1,
                  do: "posição",
                  else: "posições"}
              </small>
            </div>
            <div class="snapshot-category-share">
              <span>{allocation_percent(@latest.other_investments_cents, @latest)}%</span>
              <i style={"width: #{allocation_percent(@latest.other_investments_cents, @latest)}%"}>
              </i>
            </div>
          </article>
        </section>

        <section class="snapshot-chart-card">
          <div class="snapshot-section-heading">
            <div>
              <span class="snapshot-section-icon">
                <.icon name="hero-chart-bar-square-mini" class="size-4" />
              </span>
              <div>
                <strong>Evolução do patrimônio</strong>
                <small>Valor líquido consolidado em cada sincronização</small>
              </div>
            </div>
            <span>
              {@snapshots |> length()} {if length(@snapshots) == 1, do: "snapshot", else: "snapshots"}
            </span>
          </div>
          <div class="snapshot-chart-scroll">
            <svg
              class="snapshot-chart"
              viewBox="0 0 960 270"
              role="img"
              aria-label="Gráfico da evolução do patrimônio"
            >
              <defs>
                <linearGradient id="snapshot-area-gradient" x1="0" x2="0" y1="0" y2="1">
                  <stop offset="0%" stop-color="#769274" stop-opacity=".3" />
                  <stop offset="100%" stop-color="#769274" stop-opacity=".02" />
                </linearGradient>
              </defs>
              <g :for={tick <- @chart.ticks}>
                <line x1="74" x2="930" y1={tick.y} y2={tick.y} class="snapshot-grid-line" />
                <text x="64" y={tick.y + 3} class="snapshot-axis-value">
                  {Format.money(tick.value)}
                </text>
              </g>
              <path d={@chart.area_path} class="snapshot-area" />
              <polyline points={@chart.point_string} class="snapshot-line" />
              <g :for={point <- @chart.points}>
                <circle cx={point.x} cy={point.y} r="4.5" class="snapshot-point">
                  <title>
                    {snapshot_datetime(point.snapshot.captured_at)} — {Format.money(
                      point.snapshot.total_cents
                    )}
                  </title>
                </circle>
                <text
                  :if={point.show_label}
                  x={point.x}
                  y="250"
                  class="snapshot-axis-date"
                  text-anchor="middle"
                >
                  {chart_date(point.snapshot.captured_at)}
                </text>
              </g>
            </svg>
          </div>
        </section>

        <section class="snapshot-history" aria-label="Histórico de snapshots">
          <div class="snapshot-section-heading history-heading">
            <div>
              <span class="snapshot-section-icon">
                <.icon name="hero-clock-mini" class="size-4" />
              </span>
              <div>
                <strong>Histórico completo</strong>
                <small>Abra uma linha para conferir os valores que foram preservados.</small>
              </div>
            </div>
          </div>

          <article
            :for={snapshot <- @history_rows}
            id={"snapshot-#{snapshot.id}"}
            class="snapshot-history-row"
          >
            <button
              type="button"
              class="snapshot-row-summary"
              phx-click="toggle_details"
              phx-value-id={snapshot.id}
              aria-expanded={@expanded_id == snapshot.id}
            >
              <span class="snapshot-date-mark"><i></i></span>
              <span class="snapshot-row-date">
                <strong>{snapshot_datetime(snapshot.captured_at)}</strong>
                <small>
                  {snapshot.cash_count + snapshot.stocks_count + snapshot.other_investments_count} posições
                </small>
              </span>
              <span class="snapshot-row-composition" aria-label="Composição">
                <i class="cash" style={"width: #{allocation_percent(snapshot.cash_cents, snapshot)}%"}>
                </i>
                <i
                  class="stocks"
                  style={"width: #{allocation_percent(snapshot.stocks_cents, snapshot)}%"}
                >
                </i>
                <i
                  class="other"
                  style={"width: #{allocation_percent(snapshot.other_investments_cents, snapshot)}%"}
                >
                </i>
              </span>
              <span class={["snapshot-row-change", trend_class(snapshot.change_cents)]}>
                <small>Variação</small>
                <strong>{signed_money(snapshot.change_cents)}</strong>
              </span>
              <span class="snapshot-row-total">
                <small>Patrimônio</small>
                <strong>{Format.money(snapshot.total_cents)}</strong>
              </span>
              <.icon
                name={
                  if @expanded_id == snapshot.id,
                    do: "hero-chevron-up-mini",
                    else: "hero-chevron-down-mini"
                }
                class="size-4 snapshot-chevron"
              />
            </button>

            <div :if={@expanded_id == snapshot.id} class="snapshot-details">
              <section :for={
                {category, label, icon} <- [
                  {"cash", "Caixa", "hero-banknotes-mini"},
                  {"stocks", "Ações", "hero-presentation-chart-line-mini"},
                  {"other_investments", "Outros investimentos", "hero-circle-stack-mini"}
                ]
              }>
                <div class="snapshot-detail-heading">
                  <span><.icon name={icon} class="size-4" /> {label}</span>
                  <strong>
                    {Format.money(category_total(snapshot, category))}
                  </strong>
                </div>
                <div :if={category_items(snapshot, category) == []} class="snapshot-detail-empty">
                  Nenhuma posição registrada
                </div>
                <div :for={item <- category_items(snapshot, category)} class="snapshot-detail-row">
                  <div>
                    <strong>{if item.ticker, do: item.ticker, else: item.name}</strong>
                    <small>
                      {if item.ticker,
                        do: item.name <> " · " <> item_caption(item),
                        else: item_caption(item)}
                    </small>
                  </div>
                  <strong class={item.value_cents < 0 && "negative"}>
                    {Format.money(item.value_cents)}
                  </strong>
                </div>
              </section>
            </div>
          </article>
        </section>
      <% else %>
        <section class="snapshot-empty">
          <div class="snapshot-empty-visual" aria-hidden="true">
            <span><.icon name="hero-chart-bar-square" class="size-8" /></span>
            <i></i><i></i><i></i><i></i>
          </div>
          <div>
            <p class="eyebrow">Seu ponto de partida</p>
            <h2>Registre o primeiro retrato do patrimônio</h2>
            <p>
              A sincronização soma o caixa, as ações com posição e os outros investimentos.
              Depois, cada novo retrato revela sua evolução sem alterar os anteriores.
            </p>
            <button type="button" class="primary-action" phx-click="sync">
              <.icon name="hero-camera-mini" class="size-4" /> Criar primeiro snapshot
            </button>
          </div>
        </section>
      <% end %>
    </Layouts.app>
    """
  end
end
