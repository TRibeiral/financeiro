defmodule Financeiro.Importer do
  @moduledoc "Imports supported bank exports into the normalized local ledger."

  alias Financeiro.Repo
  alias Financeiro.Importer.Parsers
  alias Financeiro.Ledger.{Import, LunaClassifier, Transaction}

  @extensions ~w(.csv .xlsx .pdf)

  def import(path, opts \\ []) do
    cond do
      File.dir?(path) -> import_directory(path, opts)
      File.regular?(path) -> import_file(path, opts)
      true -> {:error, "caminho não encontrado: #{path}"}
    end
  end

  def import_directory(path, opts \\ []) do
    results =
      path
      |> File.ls!()
      |> Enum.map(&Path.join(path, &1))
      |> Enum.filter(&(File.regular?(&1) and String.downcase(Path.extname(&1)) in @extensions))
      |> Enum.sort()
      |> Enum.map(&import_file(&1, opts))

    {:ok, summarize(results), results}
  end

  def import_file(path, opts \\ []) do
    hash = path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    case Repo.get_by(Import, file_hash: hash) do
      %Import{} = previous -> {:skipped, previous}
      nil -> parse_and_store(path, hash, opts)
    end
  rescue
    error -> {:error, Path.basename(path), Exception.message(error)}
  end

  defp parse_and_store(path, hash, opts) do
    case Parsers.parse(path, opts) do
      {:ok, rows, metadata} ->
        changes = %{
          filename: Path.basename(path),
          path: Path.expand(path),
          file_hash: hash,
          bank: metadata.bank,
          owner: metadata.owner,
          status: "processing",
          ignored_count: metadata.ignored
        }

        case %Import{} |> Import.changeset(changes) |> Repo.insert() do
          {:ok, import} ->
            store_rows(import, rows, path)

          {:error, %{errors: [file_hash: _]}} ->
            {:skipped, Repo.get_by!(Import, file_hash: hash)}

          {:error, changeset} ->
            {:error, Path.basename(path), inspect(changeset.errors)}
        end

      {:error, reason} ->
        %Import{}
        |> Import.changeset(%{
          filename: Path.basename(path),
          path: Path.expand(path),
          file_hash: hash,
          status: "error",
          error: reason
        })
        |> Repo.insert()

        {:error, Path.basename(path), reason}
    end
  end

  defp store_rows(import, rows, path) do
    {transaction_ids, duplicates} = insert_rows(rows, import, path)
    inserted = length(transaction_ids)

    classification_error =
      case LunaClassifier.classify_pending(ids: transaction_ids) do
        {:ok, _summary} -> nil
        {:error, reason, _summary} -> "Classificação Luna pendente: #{reason}"
      end

    {:ok, import} =
      import
      |> Import.changeset(%{
        status: "completed",
        inserted_count: inserted,
        duplicate_count: duplicates,
        error: classification_error
      })
      |> Repo.update()

    {:ok, import}
  rescue
    error ->
      message = Exception.message(error)

      import
      |> Import.changeset(%{status: "error", error: message})
      |> Repo.update()

      {:error, Path.basename(path), message}
  end

  defp insert_rows(rows, import, path) do
    Enum.reduce(rows, {[], 0}, fn attrs, {transaction_ids, duplicates} ->
      fingerprint = fingerprint(attrs)

      changes =
        Map.merge(attrs, %{
          source_file: Path.basename(path),
          import_id: import.id,
          fingerprint: fingerprint
        })

      case %Transaction{} |> Transaction.changeset(changes) |> Repo.insert() do
        {:ok, transaction} ->
          {[transaction.id | transaction_ids], duplicates}

        {:error, changeset} ->
          if Keyword.has_key?(changeset.errors, :fingerprint),
            do: {transaction_ids, duplicates + 1},
            else: raise(inspect(changeset.errors))
      end
    end)
  end

  defp fingerprint(attrs) do
    identity =
      if attrs.source_identifier not in [nil, ""] do
        [attrs.bank, attrs.owner, attrs.source_type, attrs.source_identifier]
      else
        [
          attrs.bank,
          attrs.owner,
          attrs.account_ref,
          attrs.source_type,
          attrs.occurred_on,
          attrs.amount_cents,
          attrs.merchant_key
        ]
      end

    identity |> Enum.join("|") |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp summarize(results) do
    Enum.reduce(
      results,
      %{files: length(results), inserted: 0, duplicates: 0, skipped: 0, errors: 0},
      fn
        {:ok, import}, acc ->
          %{
            acc
            | inserted: acc.inserted + import.inserted_count,
              duplicates: acc.duplicates + import.duplicate_count
          }

        {:skipped, _}, acc ->
          %{acc | skipped: acc.skipped + 1}

        {:error, _, _}, acc ->
          %{acc | errors: acc.errors + 1}

        _, acc ->
          acc
      end
    )
  end
end
