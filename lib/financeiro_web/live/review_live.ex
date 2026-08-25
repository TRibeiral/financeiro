defmodule FinanceiroWeb.ReviewLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket), do: {:ok, reload(socket)}

  @impl true
  def handle_event("choose", %{"category" => category}, socket),
    do: {:noreply, assign(socket, selected: category)}

  def handle_event(
        "approve",
        _params,
        %{assigns: %{current: current, selected: selected}} = socket
      ) do
    {:ok, _} = Ledger.review_transaction(current, selected)
    {:noreply, socket |> put_flash(:info, "Categoria confirmada") |> reload()}
  end

  def handle_event(
        "approve_similar",
        _params,
        %{assigns: %{current: current, selected: selected}} = socket
      ) do
    count = Ledger.review_similar(current, selected)

    {:noreply,
     socket |> put_flash(:info, "#{count} lançamentos semelhantes confirmados") |> reload()}
  end

  def handle_event("skip", _params, socket) do
    [_ | rest] = socket.assigns.queue
    queue = rest ++ [socket.assigns.current]

    {:noreply,
     assign(socket,
       queue: queue,
       current: List.first(queue),
       selected: List.first(queue).category
     )}
  end

  def handle_event("undo", _params, socket) do
    {:ok, count} = Ledger.undo_action(Ledger.latest_undo_action())

    message =
      if count == 1,
        do: "Última confirmação desfeita",
        else: "#{count} confirmações semelhantes desfeitas"

    {:noreply, socket |> put_flash(:info, message) |> reload()}
  end

  defp reload(socket) do
    queue = Ledger.list_review_queue()
    current = List.first(queue)

    assign(socket,
      page_title: "Revisão",
      queue: queue,
      current: current,
      selected: current && current.category,
      categories: Ledger.categories(),
      undo_available: not is_nil(Ledger.latest_undo_action()),
      pending: length(queue)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="review" pending={@pending}>
      <div class="review-page">
        <div class="page-heading review-heading">
          <div>
            <p class="eyebrow">Fila inteligente</p>
            <h1>Revisar categorias</h1>
            <p>Uma decisão por vez. O sistema aprende com cada confirmação.</p>
          </div>
          <div class="heading-actions">
            <button :if={@undo_available} phx-click="undo" class="secondary-action">
              <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Desfazer última
            </button>
            <div class="queue-count"><strong>{@pending}</strong><span>pendentes</span></div>
          </div>
        </div>

        <%= if @current do %>
          <div class="review-progress">
            <span style={"width: #{max(6, 100 - min(@pending, 100))}%"}></span>
          </div>
          <section class="review-card">
            <div class="review-context">
              <span>{Format.date(@current.occurred_on)}</span><i></i><span>{@current.bank}</span><i></i><span>{@current.owner}</span>
            </div>
            <h2>{@current.description}</h2>
            <div class={["review-amount", @current.amount_cents < 0 && "credit"]}>
              {Format.money(@current.amount_cents)}
            </div>
            <p class="review-origin">{@current.source_type} · {@current.account_ref}</p>

            <div class="suggestion-label">
              <span>Sugestão automática</span><small>{@current.classification_confidence}% de confiança</small>
            </div>
            <div class="category-grid">
              <button
                :for={category <- @categories}
                phx-click="choose"
                phx-value-category={category}
                class={["category-choice", @selected == category && "selected"]}
              >
                <span>{category_icon(category)}</span>{category}<.icon
                  :if={@selected == category}
                  name="hero-check-circle-solid"
                  class="size-5"
                />
              </button>
            </div>

            <div class="review-actions">
              <button phx-click="skip" class="secondary-action">Pular por enquanto</button>
              <button phx-click="approve_similar" class="secondary-action">
                Confirmar semelhantes
              </button>
              <button phx-click="approve" class="primary-action">
                Confirmar categoria <.icon name="hero-check-mini" class="size-4" />
              </button>
            </div>
            <details class="source-peek">
              <summary>Ver dados originais</summary>
              <pre>{Jason.encode!(@current.raw_data, pretty: true)}</pre>
            </details>
          </section>
          <p class="keyboard-hint">
            A fila começa pelos lançamentos mais recentes · “Confirmar semelhantes” aplica a decisão ao mesmo estabelecimento.
          </p>
        <% else %>
          <div class="review-complete">
            <span>✓</span>
            <h2>Tudo revisado</h2>
            <p>Nenhum lançamento está esperando por você.</p>
            <.link navigate={~p"/"} class="primary-action">Voltar aos lançamentos</.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp category_icon("Casa"), do: "⌂"
  defp category_icon("Funcionarios"), do: "◉"
  defp category_icon("Mercado"), do: "◫"
  defp category_icon("Restaurante"), do: "◌"
  defp category_icon("Transporte"), do: "↗"
  defp category_icon("Saude"), do: "+"
  defp category_icon("Extras"), do: "✦"
  defp category_icon("Filho"), do: "☺"
  defp category_icon("Viagem"), do: "⌁"
  defp category_icon("Pet"), do: "◇"
  defp category_icon(_), do: "•••"
end
