defmodule FinanceiroWeb.ImportsLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias Financeiro.Ledger.LunaClassifier

  @impl true
  def mount(_params, _session, socket), do: {:ok, reload(socket)}

  @impl true
  def handle_event("scan", _params, socket) do
    result =
      if Process.whereis(Financeiro.ImportWatcher) do
        Financeiro.ImportWatcher.scan_now()
      else
        Financeiro.Importer.import(Application.fetch_env!(:financeiro, :statements_dir))
      end

    message =
      case result do
        {:ok, summary, _} ->
          "#{summary.inserted} novos lançamentos; #{summary.skipped} arquivos já conhecidos"

        _ ->
          "Verificação concluída"
      end

    {:noreply, socket |> put_flash(:info, message) |> reload()}
  end

  @impl true
  def handle_event("classify", _params, socket) do
    message =
      case LunaClassifier.classify_pending() do
        {:ok, %{classified: count}} -> "Luna classificou #{count} lançamentos"
        {:error, reason, _summary} -> "Não foi possível concluir com Luna: #{reason}"
      end

    {:noreply, socket |> put_flash(:info, message) |> reload()}
  end

  defp reload(socket),
    do:
      assign(socket,
        page_title: "Importações",
        active: "imports",
        imports: Ledger.list_imports(),
        pending: Ledger.pending_count(),
        luna_pending: LunaClassifier.pending_luna_count(),
        luna_model: Financeiro.CodexRunner.model(),
        directory: Application.fetch_env!(:financeiro, :statements_dir)
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="imports" pending={@pending}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">Entrada de dados</p>
          <h1>Importações</h1>
          <p>Solte novos extratos na pasta. O app verifica mudanças automaticamente.</p>
        </div>
        <div class="heading-actions">
          <button phx-click="classify" class="secondary-action" disabled={@luna_pending == 0}>
            <.icon name="hero-sparkles-mini" class="size-4" /> Luna ({@luna_pending})
          </button>
          <button phx-click="scan" class="primary-action">
            <.icon name="hero-arrow-path-mini" class="size-4" /> Verificar agora
          </button>
        </div>
      </div>
      <section class="drop-zone">
        <div class="folder-icon"><.icon name="hero-folder-arrow-down" class="size-8" /></div>
        <div>
          <span>Pasta monitorada a cada 15 segundos</span><strong>{@directory}</strong><small>CSV Nubank · XLSX Itaú cartão · PDF Itaú conta</small>
        </div>
      </section>
      <div class="import-command">
        <span>Codex da assinatura · {@luna_model}</span><code>mix financeiro.classify</code><code>mix financeiro.import ../extratos --owner "Nome"</code>
      </div>

      <section class="imports-list">
        <div class="section-title">
          <h2>Histórico de arquivos</h2>
          <span>{length(@imports)} registros recentes</span>
        </div>
        <article :for={import <- @imports} class="import-row">
          <div class={["file-status", import.status]}>
            {if import.status == "completed", do: "✓", else: "!"}
          </div>
          <div class="file-info">
            <strong>{import.filename}</strong><span>{import.bank || "Formato não reconhecido"} · {import.owner || "Pessoa não identificada"}</span><small :if={
              import.error
            }>{import.error}</small>
          </div>
          <div class="import-numbers"><strong>{import.inserted_count}</strong><span>novos</span></div>
          <div class="import-numbers">
            <strong>{import.duplicate_count}</strong><span>duplicados</span>
          </div>
          <div class="import-numbers">
            <strong>{import.ignored_count}</strong><span>antes de 01/08</span>
          </div>
        </article>
        <div :if={@imports == []} class="empty-state">
          <strong>Nenhum arquivo importado ainda</strong>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
