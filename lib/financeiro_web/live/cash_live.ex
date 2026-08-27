defmodule FinanceiroWeb.CashLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Cash
  alias Financeiro.Cash.Balance
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Caixa",
       pending: Ledger.pending_count(),
       editing_id: nil,
       edit_form: nil
     )
     |> new_form()
     |> reload()}
  end

  @impl true
  def handle_event("create", %{"balance" => attrs}, socket) do
    case Cash.create_balance(attrs) do
      {:ok, _balance} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saldo adicionado")
         |> new_form()
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, new_form: to_form(changeset, as: :balance))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    balance = Cash.get_balance!(id)

    {:noreply,
     assign(socket,
       editing_id: balance.id,
       edit_form: to_form(Cash.change_balance(balance), as: :balance)
     )}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_form: nil)}
  end

  def handle_event("update", %{"balance_id" => id, "balance" => attrs}, socket) do
    balance = Cash.get_balance!(id)

    case Cash.update_balance(balance, attrs) do
      {:ok, _balance} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saldo atualizado")
         |> assign(editing_id: nil, edit_form: nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           editing_id: balance.id,
           edit_form: to_form(changeset, as: :balance)
         )}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    balance = Cash.get_balance!(id)
    {:ok, _balance} = Cash.delete_balance(balance)

    {:noreply,
     socket
     |> put_flash(:info, "#{balance.name} removido")
     |> assign(editing_id: nil, edit_form: nil)
     |> reload()}
  end

  defp new_form(socket) do
    assign(socket, new_form: to_form(Cash.change_balance(%Balance{}), as: :balance))
  end

  defp reload(socket) do
    balances = Cash.list_balances()
    assign(socket, balances: balances, summary: Cash.summary(balances))
  end

  defp field_error(form, field) do
    case Keyword.get(form.errors, field) do
      nil -> nil
      {message, _opts} -> message
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="cash" pending={@pending}>
      <div class="page-heading cash-heading">
        <div>
          <p class="eyebrow">Disponibilidades & obrigações</p>
          <h1>Caixa</h1>
          <p>Saldos de contas, dinheiro disponível e valores a pagar.</p>
        </div>
      </div>

      <section class={[
        "cash-hero",
        @summary.total < 0 && "negative"
      ]}>
        <div class="cash-total">
          <span>Saldo líquido</span>
          <strong id="cash-total">{Format.money(@summary.total)}</strong>
          <small>Ativos menos obrigações</small>
        </div>
        <div class="cash-metrics">
          <div>
            <span>Disponível</span>
            <strong>{Format.money(@summary.positive)}</strong>
          </div>
          <div>
            <span>Obrigações</span>
            <strong class={@summary.negative < 0 && "liability"}>
              {Format.money(@summary.negative)}
            </strong>
          </div>
          <div>
            <span>Linhas</span>
            <strong>{@summary.count}</strong>
          </div>
        </div>
      </section>

      <section class="cash-add-card">
        <div class="cash-section-heading">
          <div>
            <span class="cash-section-icon"><.icon name="hero-plus-mini" class="size-4" /></span>
            <div>
              <strong>Adicionar saldo</strong>
              <small>Use um valor negativo para cartões e outras obrigações.</small>
            </div>
          </div>
        </div>
        <.balance_form form={@new_form} submit="create" id="new-balance-form" />
      </section>

      <section class="cash-list" aria-label="Saldos cadastrados">
        <div class="cash-list-heading">
          <div>
            <strong>Suas contas</strong>
            <span>Atualize os valores quando precisar.</span>
          </div>
          <span>{@summary.count} {if @summary.count == 1, do: "linha", else: "linhas"}</span>
        </div>

        <div :if={@balances == []} class="cash-empty">
          <span><.icon name="hero-banknotes" class="size-8" /></span>
          <strong>Seu caixa começa aqui</strong>
          <p>Adicione acima o saldo de uma conta, carteira ou cartão.</p>
        </div>

        <article
          :for={balance <- @balances}
          id={"balance-#{balance.id}"}
          class={[
            "cash-row",
            balance.amount_cents < 0 && "liability",
            @editing_id == balance.id && "editing"
          ]}
        >
          <%= if @editing_id == balance.id do %>
            <.balance_form
              form={@edit_form}
              submit="update"
              id={"edit-balance-#{balance.id}"}
              balance_id={balance.id}
            />
          <% else %>
            <div class="cash-row-icon">
              <.icon
                name={
                  if balance.amount_cents < 0,
                    do: "hero-credit-card-mini",
                    else: "hero-building-library-mini"
                }
                class="size-5"
              />
            </div>
            <div class="cash-row-name">
              <strong>{balance.name}</strong>
              <small>{if balance.amount_cents < 0, do: "Obrigação", else: "Disponível"}</small>
            </div>
            <strong class="cash-row-amount">{Format.money(balance.amount_cents)}</strong>
            <div class="cash-row-actions">
              <button
                type="button"
                phx-click="edit"
                phx-value-id={balance.id}
                aria-label={"Editar #{balance.name}"}
                title="Editar"
              >
                <.icon name="hero-pencil-mini" class="size-4" />
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={balance.id}
                data-confirm={"Remover #{balance.name}?"}
                aria-label={"Remover #{balance.name}"}
                title="Remover"
                class="danger"
              >
                <.icon name="hero-trash-mini" class="size-4" />
              </button>
            </div>
          <% end %>
        </article>
      </section>
    </Layouts.app>
    """
  end

  attr :form, :map, required: true
  attr :submit, :string, required: true
  attr :id, :string, required: true
  attr :balance_id, :integer, default: nil

  defp balance_form(assigns) do
    ~H"""
    <form id={@id} phx-submit={@submit} class="cash-form">
      <input :if={@balance_id} type="hidden" name="balance_id" value={@balance_id} />
      <label>
        <span>Conta ou descrição</span>
        <input
          name={@form[:name].name}
          value={@form[:name].value}
          placeholder="Ex.: Nubank, carteira, cartão Itaú"
          maxlength="100"
          required
        />
        <small :if={field_error(@form, :name)}>{field_error(@form, :name)}</small>
      </label>
      <label>
        <span>Saldo em reais</span>
        <div class="cash-amount-input">
          <i>R$</i>
          <input
            name={@form[:amount].name}
            value={@form[:amount].value}
            placeholder="0,00"
            inputmode="decimal"
            autocomplete="off"
            required
          />
        </div>
        <small :if={field_error(@form, :amount)}>{field_error(@form, :amount)}</small>
      </label>
      <div class="cash-form-actions">
        <button :if={@balance_id} type="button" phx-click="cancel_edit" class="secondary-action">
          Cancelar
        </button>
        <button type="submit" class="primary-action">
          {if @balance_id, do: "Salvar", else: "Adicionar linha"}
        </button>
      </div>
    </form>
    """
  end
end
