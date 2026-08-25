defmodule Mix.Tasks.Financeiro.Import do
  use Mix.Task

  @shortdoc "Importa extratos CSV, XLSX e PDF"
  @moduledoc """
  Importa um arquivo ou pasta de extratos, ignorando duplicatas.

      mix financeiro.import ../extratos
      mix financeiro.import /caminho/extrato.csv --owner "Ana Clara"
  """

  @impl true
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, strict: [owner: :string], aliases: [o: :owner])

    case paths do
      [path] ->
        Application.put_env(:financeiro, :watch_statements, false)
        Mix.Task.run("app.start")

        result =
          Financeiro.Importer.import(path, owner: opts[:owner] || "Thiago Carneiro Ribeiral")

        Mix.shell().info(inspect(result, pretty: true))

      _ ->
        Mix.raise("uso: mix financeiro.import CAMINHO [--owner NOME]")
    end
  end
end
