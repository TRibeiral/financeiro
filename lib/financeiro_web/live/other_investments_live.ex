defmodule FinanceiroWeb.OtherInvestmentsLive do
  use FinanceiroWeb, :live_view

  alias Financeiro.Investments
  alias Financeiro.Investments.OtherInvestment
  alias Financeiro.Ledger
  alias FinanceiroWeb.Format

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Outros investimentos",
       pending: Ledger.pending_count(),
       editing_id: nil,
       edit_form: nil
     )
     |> new_form()
     |> reload()}
  end

  @impl true
  def handle_event("create", %{"investment" => attrs}, socket) do
    case Investments.create_other_investment(attrs) do
      {:ok, _investment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Investimento adicionado")
         |> new_form()
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, new_form: to_form(changeset, as: :investment))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    investment = Investments.get_other_investment!(id)

    {:noreply,
     assign(socket,
       editing_id: investment.id,
       edit_form: to_form(Investments.change_other_investment(investment), as: :investment)
     )}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, edit_form: nil)}
  end

  def handle_event("update", %{"investment_id" => id, "investment" => attrs}, socket) do
    investment = Investments.get_other_investment!(id)

    case Investments.update_other_investment(investment, attrs) do
      {:ok, _investment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Investimento atualizado")
         |> assign(editing_id: nil, edit_form: nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           editing_id: investment.id,
           edit_form: to_form(changeset, as: :investment)
         )}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    investment = Investments.get_other_investment!(id)
    {:ok, _investment} = Investments.delete_other_investment(investment)

    {:noreply,
     socket
     |> put_flash(:info, "#{investment.description} removido")
     |> assign(editing_id: nil, edit_form: nil)
     |> reload()}
  end

  defp new_form(socket) do
    form =
      %OtherInvestment{}
      |> Investments.change_other_investment()
      |> to_form(as: :investment)

    assign(socket, new_form: form)
  end

  defp reload(socket) do
    investments = Investments.list_other_investments()

    assign(socket,
      investments: investments,
      summary: Investments.other_investments_summary(investments)
    )
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
    <Layouts.app flash={@flash} active="other-investments" pending={@pending}>
      <div class="page-heading other-investments-heading">
        <div>
          <p class="eyebrow">Patrimônio fora da bolsa</p>
          <h1>Outros investimentos</h1>
          <p>Registre investimentos que não fazem parte da sua carteira de ações.</p>
        </div>
      </div>

      <section class="other-investments-hero">
        <div>
          <span>Patrimônio em outros investimentos</span>
          <strong id="other-investments-total">{Format.money(@summary.total)}</strong>
          <small>Soma dos valores cadastrados</small>
        </div>
        <div>
          <span>Investimentos</span>
          <strong>{@summary.count}</strong>
          <small>{if @summary.count == 1, do: "posição", else: "posições"}</small>
        </div>
      </section>

      <section class="cash-add-card">
        <div class="cash-section-heading">
          <div>
            <span class="cash-section-icon"><.icon name="hero-plus-mini" class="size-4" /></span>
            <div>
              <strong>Adicionar investimento</strong>
              <small>Informe apenas uma descrição e o valor atual.</small>
            </div>
          </div>
        </div>
        <.investment_form form={@new_form} submit="create" id="new-other-investment-form" />
      </section>

      <section class="cash-list" aria-label="Outros investimentos cadastrados">
        <div class="cash-list-heading">
          <div>
            <strong>Seus investimentos</strong>
            <span>Edite os valores conforme eles mudarem.</span>
          </div>
          <span>{@summary.count} {if @summary.count == 1, do: "linha", else: "linhas"}</span>
        </div>

        <div :if={@investments == []} class="cash-empty">
          <span><.icon name="hero-circle-stack" class="size-8" /></span>
          <strong>Adicione seu primeiro investimento</strong>
          <p>A lista serve para imóveis, renda fixa, fundos e outros ativos.</p>
        </div>

        <article
          :for={investment <- @investments}
          id={"other-investment-#{investment.id}"}
          class={["cash-row", @editing_id == investment.id && "editing"]}
        >
          <%= if @editing_id == investment.id do %>
            <.investment_form
              form={@edit_form}
              submit="update"
              id={"edit-other-investment-#{investment.id}"}
              investment_id={investment.id}
            />
          <% else %>
            <div class="cash-row-icon other-investment-icon">
              <.icon name="hero-circle-stack-mini" class="size-5" />
            </div>
            <div class="cash-row-name">
              <strong>{investment.description}</strong>
              <small>Investimento</small>
            </div>
            <strong class="cash-row-amount">{Format.money(investment.value_cents)}</strong>
            <div class="cash-row-actions">
              <button
                type="button"
                phx-click="edit"
                phx-value-id={investment.id}
                aria-label={"Editar #{investment.description}"}
                title="Editar"
              >
                <.icon name="hero-pencil-mini" class="size-4" />
              </button>
              <button
                type="button"
                phx-click="delete"
                phx-value-id={investment.id}
                data-confirm={"Remover #{investment.description}?"}
                aria-label={"Remover #{investment.description}"}
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
  attr :investment_id, :integer, default: nil

  defp investment_form(assigns) do
    ~H"""
    <form id={@id} phx-submit={@submit} class="cash-form">
      <input :if={@investment_id} type="hidden" name="investment_id" value={@investment_id} />
      <label>
        <span>Descrição</span>
        <input
          name={@form[:description].name}
          value={@form[:description].value}
          placeholder="Ex.: Tesouro Direto, imóvel, fundo"
          maxlength="120"
          required
        />
        <small :if={field_error(@form, :description)}>{field_error(@form, :description)}</small>
      </label>
      <label>
        <span>Valor em reais</span>
        <div class="cash-amount-input">
          <i>R$</i>
          <input
            name={@form[:value].name}
            value={@form[:value].value}
            placeholder="0,00"
            inputmode="decimal"
            autocomplete="off"
            required
          />
        </div>
        <small :if={field_error(@form, :value)}>{field_error(@form, :value)}</small>
      </label>
      <div class="cash-form-actions">
        <button
          :if={@investment_id}
          type="button"
          phx-click="cancel_edit"
          class="secondary-action"
        >
          Cancelar
        </button>
        <button type="submit" class="primary-action">
          {if @investment_id, do: "Salvar", else: "Adicionar linha"}
        </button>
      </div>
    </form>
    """
  end
end
