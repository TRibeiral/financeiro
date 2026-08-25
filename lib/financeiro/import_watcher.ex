defmodule Financeiro.ImportWatcher do
  use GenServer
  require Logger

  @interval :timer.seconds(15)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def scan_now, do: GenServer.call(__MODULE__, :scan, :timer.minutes(2))

  @impl true
  def init(opts) do
    state = %{
      directory: Keyword.fetch!(opts, :directory),
      interval: Keyword.get(opts, :interval, @interval)
    }

    send(self(), :scan)
    {:ok, state}
  end

  @impl true
  def handle_call(:scan, _from, state) do
    {:reply, run_scan(state), state}
  end

  @impl true
  def handle_info(:scan, state) do
    run_scan(state)
    Process.send_after(self(), :scan, state.interval)
    {:noreply, state}
  end

  defp run_scan(%{directory: directory}) do
    if File.dir?(directory) do
      Financeiro.Importer.import_directory(directory)
    else
      Logger.warning("Pasta de extratos não encontrada: #{directory}")
      {:error, :missing_directory}
    end
  rescue
    error ->
      Logger.error("Falha ao verificar extratos: #{Exception.message(error)}")
      {:error, error}
  end
end
