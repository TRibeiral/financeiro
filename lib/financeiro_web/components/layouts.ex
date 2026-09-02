defmodule FinanceiroWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FinanceiroWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :active, :string, default: "transactions"
  attr :pending, :integer, default: 0

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app-shell">
      <aside class="sidebar">
        <.link navigate={~p"/"} class="brand">
          <span class="brand-mark">F</span>
          <div><strong>financeiro</strong><small>pessoal & local</small></div>
        </.link>
        <nav>
          <.link navigate={~p"/"} class={@active == "transactions" && "active"}>
            <.icon name="hero-bars-3-bottom-left-mini" class="size-5" />Despesas
          </.link>
          <.link navigate={~p"/income"} class={@active == "income" && "active"}>
            <.icon name="hero-arrow-trending-up-mini" class="size-5" />Entradas
          </.link>
          <.link navigate={~p"/review"} class={@active == "review" && "active"}>
            <.icon name="hero-check-badge-mini" class="size-5" />Revisar
            <span :if={@pending > 0} class="nav-badge">{@pending}</span>
          </.link>
          <.link navigate={~p"/insights"} class={@active == "insights" && "active"}>
            <.icon name="hero-chart-bar-square-mini" class="size-5" />Análises
          </.link>
          <.link navigate={~p"/stocks"} class={@active == "stocks" && "active"}>
            <.icon name="hero-presentation-chart-line-mini" class="size-5" />Ações
          </.link>
          <.link
            navigate={~p"/other-investments"}
            class={@active == "other-investments" && "active"}
          >
            <.icon name="hero-circle-stack-mini" class="size-5" />Outros investimentos
          </.link>
          <.link navigate={~p"/cash"} class={@active == "cash" && "active"}>
            <.icon name="hero-banknotes-mini" class="size-5" />Caixa
          </.link>
          <.link navigate={~p"/cash-flow"} class={@active == "cash-flow" && "active"}>
            <.icon name="hero-arrow-path-rounded-square-mini" class="size-5" />Visão mensal
          </.link>
          <.link navigate={~p"/imports"} class={@active == "imports" && "active"}>
            <.icon name="hero-arrow-down-tray-mini" class="size-5" />Importações
          </.link>
        </nav>
        <div class="sidebar-foot">
          <span><i></i> Local</span><small>SQLite na sua máquina</small>
        </div>
      </aside>
      <main class="app-content">{render_slot(@inner_block)}</main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
