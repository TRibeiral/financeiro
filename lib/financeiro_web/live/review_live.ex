defmodule FinanceiroWeb.ReviewLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(params, _session, socket) do
    tab = if params["tab"] == "duplicates", do: "duplicates", else: "categories"
    {:ok, reload(socket, tab)}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab}, socket)
      when tab in ["categories", "duplicates"],
      do: {:noreply, assign(socket, tab: tab)}

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

  def handle_event(
        "resolve_duplicate",
        %{"first_id" => first_id, "second_id" => second_id, "keep" => keep},
        socket
      ) do
    with {first_id, ""} <- Integer.parse(first_id),
         {second_id, ""} <- Integer.parse(second_id),
         {:ok, keep_choice} <- duplicate_keep_choice(keep),
         {:ok, _result} <- Ledger.resolve_potential_duplicate(first_id, second_id, keep_choice) do
      message =
        if keep_choice == :both,
          do: "Os dois lançamentos foram mantidos",
          else: "Apenas o lançamento escolhido foi mantido"

      {:noreply, socket |> put_flash(:info, message) |> reload()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Não foi possível resolver esse possível duplicado")}
    end
  end

  defp reload(socket, tab \\ nil) do
    queue = Ledger.list_review_queue()
    current = List.first(queue)
    duplicate_queue = Ledger.list_potential_duplicates()
    duplicate_pending = length(duplicate_queue)
    category_pending = length(queue)

    assign(socket,
      page_title: "Revisão",
      tab: tab || Map.get(socket.assigns, :tab, "categories"),
      queue: queue,
      current: current,
      duplicate_queue: duplicate_queue,
      current_duplicate: List.first(duplicate_queue),
      selected: current && current.category,
      categories: Ledger.categories(),
      undo_available: not is_nil(Ledger.latest_undo_action()),
      category_pending: category_pending,
      duplicate_pending: duplicate_pending,
      pending: category_pending + duplicate_pending
    )
  end

  defp duplicate_keep_choice("both"), do: {:ok, :both}

  defp duplicate_keep_choice(id) do
    case Integer.parse(id) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="review" pending={@pending}>
      <div class="review-page">
        <div class="page-heading review-heading">
          <div>
            <p class="eyebrow">Fila inteligente</p>
            <h1>Revisar</h1>
            <p>Categorias e possíveis duplicados, uma decisão por vez.</p>
          </div>
          <div class="heading-actions">
            <button :if={@undo_available} phx-click="undo" class="secondary-action">
              <.icon name="hero-arrow-uturn-left-mini" class="size-4" /> Desfazer última
            </button>
            <div class="queue-count"><strong>{@pending}</strong><span>pendências</span></div>
          </div>
        </div>

        <nav class="review-tabs" role="tablist" aria-label="Tipos de revisão">
          <button
            role="tab"
            aria-selected={to_string(@tab == "categories")}
            phx-click="select_tab"
            phx-value-tab="categories"
            class={@tab == "categories" && "active"}
          >
            Categorias <span>{@category_pending}</span>
          </button>
          <button
            role="tab"
            aria-selected={to_string(@tab == "duplicates")}
            phx-click="select_tab"
            phx-value-tab="duplicates"
            class={@tab == "duplicates" && "active"}
          >
            Possíveis duplicados <span>{@duplicate_pending}</span>
          </button>
        </nav>

        <%= if @tab == "categories" and @current do %>
          <div class="review-progress">
            <span style={"width: #{max(6, 100 - min(@category_pending, 100))}%"}></span>
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
        <% end %>

        <%= if @tab == "categories" and is_nil(@current) do %>
          <div class="review-complete">
            <span>✓</span>
            <h2>{if @pending == 0, do: "Tudo revisado", else: "Categorias revisadas"}</h2>
            <p>Nenhuma categoria está esperando por você.</p>
            <button
              :if={@duplicate_pending > 0}
              phx-click="select_tab"
              phx-value-tab="duplicates"
              class="primary-action"
            >
              Revisar possíveis duplicados
            </button>
            <.link navigate={~p"/"} class="primary-action">Voltar aos lançamentos</.link>
          </div>
        <% end %>

        <%= if @tab == "duplicates" and @current_duplicate do %>
          <section class="duplicate-review-card">
            <header>
              <div>
                <p class="eyebrow">Comparação lado a lado</p>
                <h2>Estes lançamentos são a mesma despesa?</h2>
                <p>Confira data, valor e origem antes de decidir.</p>
              </div>
              <span class="duplicate-confidence">
                {@current_duplicate.first.anomaly_confidence ||
                  @current_duplicate.second.anomaly_confidence || 0}% de confiança
              </span>
            </header>

            <div class="duplicate-reason">
              <.icon name="hero-sparkles-mini" class="size-5" />
              <span>
                {@current_duplicate.first.anomaly_reason || @current_duplicate.second.anomaly_reason}
              </span>
            </div>

            <div class="duplicate-comparison">
              <.duplicate_transaction
                transaction={@current_duplicate.first}
                first_id={@current_duplicate.first.id}
                second_id={@current_duplicate.second.id}
              />
              <div class="duplicate-versus">ou</div>
              <.duplicate_transaction
                transaction={@current_duplicate.second}
                first_id={@current_duplicate.first.id}
                second_id={@current_duplicate.second.id}
              />
            </div>

            <div class="duplicate-both-action">
              <button
                phx-click="resolve_duplicate"
                phx-value-first_id={@current_duplicate.first.id}
                phx-value-second_id={@current_duplicate.second.id}
                phx-value-keep="both"
                class="secondary-action"
              >
                <.icon name="hero-check-circle-mini" class="size-4" /> Manter os dois
              </button>
              <small>Use esta opção se forem duas compras legítimas.</small>
            </div>
          </section>
          <p class="keyboard-hint">
            Ao manter apenas um, o outro fica excluído dos totais, mas seus dados de origem são preservados.
          </p>
        <% end %>

        <%= if @tab == "duplicates" and is_nil(@current_duplicate) do %>
          <div class="review-complete">
            <span>✓</span>
            <h2>Duplicados revisados</h2>
            <p>Nenhum possível duplicado está esperando por você.</p>
            <button
              :if={@category_pending > 0}
              phx-click="select_tab"
              phx-value-tab="categories"
              class="primary-action"
            >
              Revisar categorias
            </button>
            <.link :if={@category_pending == 0} navigate={~p"/"} class="primary-action">
              Voltar aos lançamentos
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :transaction, :map, required: true
  attr :first_id, :integer, required: true
  attr :second_id, :integer, required: true

  defp duplicate_transaction(assigns) do
    ~H"""
    <article class="duplicate-transaction" data-transaction-id={@transaction.id}>
      <div class="duplicate-transaction-heading">
        <span>{Format.date(@transaction.occurred_on)}</span>
        <strong>{Format.money(@transaction.amount_cents)}</strong>
      </div>
      <h3>{@transaction.description}</h3>
      <dl>
        <div>
          <dt>Banco</dt>
          <dd>{@transaction.bank}</dd>
        </div>
        <div>
          <dt>Pessoa</dt>
          <dd>{@transaction.owner}</dd>
        </div>
        <div>
          <dt>Origem</dt>
          <dd>{@transaction.source_type} · {@transaction.account_ref}</dd>
        </div>
        <div>
          <dt>Arquivo</dt>
          <dd>{@transaction.source_file}</dd>
        </div>
      </dl>
      <details class="source-peek">
        <summary>Ver dados originais</summary>
        <pre>{Jason.encode!(@transaction.raw_data, pretty: true)}</pre>
      </details>
      <button
        phx-click="resolve_duplicate"
        phx-value-first_id={@first_id}
        phx-value-second_id={@second_id}
        phx-value-keep={@transaction.id}
        class="primary-action"
      >
        Manter apenas este
      </button>
    </article>
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
  defp category_icon("Projetos"), do: "▦"
  defp category_icon(_), do: "•••"
end
