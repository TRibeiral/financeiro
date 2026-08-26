defmodule FinanceiroWeb.ImportsLive do
  use FinanceiroWeb, :live_view
  alias Financeiro.Ledger
  alias Financeiro.Ledger.LunaClassifier

  @nubank_owners %{
    "ana" => "Ana Clara De Paiva",
    "thiago" => "Thiago Carneiro Ribeiral"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      allow_upload(socket, :statements,
        accept: ~w(.csv .xlsx .pdf),
        max_entries: 10,
        max_file_size: 30_000_000,
        auto_upload: true,
        progress: &handle_upload_progress/3
      )

    {:ok, reload(socket)}
  end

  @impl true
  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :statements, ref)}

  def handle_event("confirm-nubank-owner", %{"ref" => ref, "owner" => owner_key}, socket) do
    with {:ok, owner} <- Map.fetch(@nubank_owners, owner_key),
         %{} = entry <- Enum.find(socket.assigns.uploads.statements.entries, &(&1.ref == ref)),
         true <- entry.done? and nubank_upload?(entry) do
      import_upload(socket, entry, owner: owner)
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível confirmar o titular")}
    end
  end

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

  defp handle_upload_progress(:statements, entry, socket) do
    cond do
      not entry.done? -> {:noreply, socket}
      nubank_upload?(entry) -> {:noreply, socket}
      true -> import_upload(socket, entry)
    end
  end

  defp import_upload(socket, entry, opts \\ []) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: temp_path} ->
        {:ok, Financeiro.Importer.store_and_import_upload(temp_path, entry.client_name, opts)}
      end)

    {:noreply,
     socket
     |> put_upload_flash(entry.client_name, result)
     |> reload()}
  end

  # Every supported CSV format is a Nubank export. Itaú exports are XLSX or PDF.
  defp nubank_upload?(entry),
    do: String.downcase(Path.extname(entry.client_name)) == ".csv"

  defp put_upload_flash(socket, filename, {:ok, %{import_result: {:ok, import}}}) do
    put_flash(
      socket,
      :info,
      "#{filename} movido para a pasta de extratos; #{import.inserted_count} novos lançamentos"
    )
  end

  defp put_upload_flash(socket, filename, {:ok, %{import_result: {:skipped, _import}}}) do
    put_flash(socket, :info, "#{filename} já estava na pasta e já havia sido importado")
  end

  defp put_upload_flash(socket, filename, {:ok, %{import_result: {:error, _, reason}}}) do
    put_flash(socket, :error, "#{filename} foi movido, mas não pôde ser importado: #{reason}")
  end

  defp put_upload_flash(socket, filename, {:error, reason}) do
    put_flash(socket, :error, "Não foi possível mover #{filename}: #{reason}")
  end

  defp put_upload_flash(socket, filename, other) do
    put_flash(socket, :error, "Não foi possível importar #{filename}: #{inspect(other)}")
  end

  defp upload_error(:too_large), do: "arquivo maior que 30 MB"
  defp upload_error(:not_accepted), do: "use um arquivo CSV, XLSX ou PDF"
  defp upload_error(:too_many_files), do: "selecione no máximo 10 arquivos por vez"
  defp upload_error(error), do: to_string(error)

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
      <form id="statement-upload" phx-change="validate-upload" class="upload-form">
        <label class="drop-zone" phx-drop-target={@uploads.statements.ref}>
          <.live_file_input
            upload={@uploads.statements}
            class="drop-input"
          />
          <div class="folder-icon"><.icon name="hero-folder-arrow-down" class="size-8" /></div>
          <div>
            <span>Solte os arquivos aqui ou clique para escolher</span><strong>{@directory}</strong><small>CSV Nubank pede confirmação do titular · XLSX e PDF Itaú são automáticos</small>
          </div>
        </label>

        <div :if={@uploads.statements.entries != []} class="upload-queue">
          <div :for={entry <- @uploads.statements.entries} class="upload-entry">
            <div class="upload-entry-name">
              <strong>{entry.client_name}</strong>
              <span>{entry.progress}%</span>
            </div>
            <progress value={entry.progress} max="100">{entry.progress}%</progress>
            <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref}>
              Cancelar
            </button>
            <div :if={entry.done? and nubank_upload?(entry)} class="owner-confirmation">
              <span>Este arquivo Nubank é de quem?</span>
              <button
                type="button"
                phx-click="confirm-nubank-owner"
                phx-value-ref={entry.ref}
                phx-value-owner="ana"
              >
                Ana
              </button>
              <button
                type="button"
                phx-click="confirm-nubank-owner"
                phx-value-ref={entry.ref}
                phx-value-owner="thiago"
              >
                Thiago
              </button>
            </div>
            <small :for={error <- upload_errors(@uploads.statements, entry)}>
              {upload_error(error)}
            </small>
          </div>
        </div>

        <p :for={error <- upload_errors(@uploads.statements)} class="upload-error">
          {upload_error(error)}
        </p>
      </form>
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
            <strong>{import.ignored_count}</strong><span>antes de 05/08</span>
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
