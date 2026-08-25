defmodule Financeiro.Importer.Parsers do
  @moduledoc false

  alias Financeiro.Ledger.{Classifier, InternalTransfer}

  @start_date ~D[2026-08-01]

  def parse(path, opts \\ []) do
    owner = Keyword.get(opts, :owner, "Thiago Carneiro Ribeiral")
    start_date = Keyword.get(opts, :start_date, @start_date)

    case String.downcase(Path.extname(path)) do
      ".csv" -> parse_csv(path, owner, start_date)
      ".xlsx" -> parse_xlsx(path, owner, start_date)
      ".pdf" -> parse_itau_pdf(path, owner, start_date)
      extension -> {:error, "formato não suportado: #{extension}"}
    end
  end

  defp parse_csv(path, owner, start_date) do
    [header | lines] =
      path |> File.read!() |> String.replace("\r\n", "\n") |> String.split("\n", trim: true)

    headers = parse_csv_line(header)

    cond do
      headers == ["Data", "Valor", "Identificador", "Descrição"] ->
        rows =
          lines
          |> Enum.map(&parse_csv_line/1)
          |> Enum.filter(&(length(&1) >= 4))
          |> Enum.map(fn [date, amount, identifier | description_parts] ->
            description = Enum.join(description_parts, ",")
            raw_cents = money_to_cents(amount)

            attrs(date_br(date), -raw_cents, description,
              bank: "Nubank",
              owner: owner,
              source_type: "conta",
              source_identifier: identifier,
              account_ref: "Conta Nubank",
              raw_data: %{
                "Data" => date,
                "Valor" => amount,
                "Identificador" => identifier,
                "Descrição" => description
              }
            )
          end)

        {:ok, filter_date(rows, start_date),
         %{
           bank: "Nubank",
           owner: owner,
           ignored: length(rows) - length(filter_date(rows, start_date))
         }}

      headers == ["date", "title", "amount"] ->
        rows =
          lines
          |> Enum.map(&parse_csv_line/1)
          |> Enum.filter(&(length(&1) == 3))
          |> Enum.map(fn [date, description, amount] ->
            attrs(Date.from_iso8601!(date), money_to_cents(amount), description,
              bank: "Nubank",
              owner: owner,
              source_type: "cartão",
              account_ref: "Cartão Nubank",
              raw_data: %{"date" => date, "title" => description, "amount" => amount}
            )
          end)

        {:ok, filter_date(rows, start_date),
         %{
           bank: "Nubank",
           owner: owner,
           ignored: length(rows) - length(filter_date(rows, start_date))
         }}

      true ->
        {:error, "CSV não reconhecido (cabeçalhos: #{Enum.join(headers, ", ")})"}
    end
  end

  defp parse_xlsx(path, fallback_owner, start_date) do
    with {:ok, files} <- :zip.extract(String.to_charlist(path), [:memory]),
         {:ok, shared_xml} <- zip_file(files, "xl/sharedStrings.xml"),
         {:ok, sheet_xml} <- zip_file(files, "xl/worksheets/sheet1.xml") do
      shared = shared_strings(shared_xml)

      rows =
        Regex.scan(~r/<row\b[^>]*>(.*?)<\/row>/s, sheet_xml, capture: :all_but_first)
        |> Enum.map(fn [row_xml] -> decode_row(row_xml, shared) end)
        |> Enum.filter(fn row ->
          Map.has_key?(row, "B") and Map.has_key?(row, "C") and Map.has_key?(row, "E")
        end)
        |> Enum.flat_map(fn row ->
          with {serial, ""} <- Float.parse(to_string(row["B"])),
               {amount, ""} <- Float.parse(to_string(row["E"])),
               true <- serial > 40_000,
               description when description not in [nil, "", "Lançamento", "Subtotal  "] <-
                 row["C"] do
            date = Date.add(~D[1899-12-30], trunc(serial))
            owner = clean_owner(row["H"] || fallback_owner)
            account_ref = [row["I"], row["J"]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

            [
              attrs(date, round(amount * 100), String.trim(description),
                bank: "Itaú",
                owner: owner,
                source_type: "cartão",
                account_ref: account_ref,
                raw_data: %{
                  "data_serial" => row["B"],
                  "lançamento" => description,
                  "parcelamento" => row["D"],
                  "valor" => row["E"],
                  "titularidade" => row["G"],
                  "nome" => row["H"],
                  "tipo_cartão" => row["I"],
                  "número_cartão" => row["J"]
                }
              )
            ]
          else
            _ -> []
          end
        end)

      filtered = filter_date(rows, start_date)
      owners = filtered |> Enum.map(& &1.owner) |> Enum.uniq()

      {:ok, filtered,
       %{bank: "Itaú", owner: Enum.join(owners, ", "), ignored: length(rows) - length(filtered)}}
    else
      {:error, reason} -> {:error, "não foi possível ler XLSX: #{inspect(reason)}"}
    end
  end

  defp parse_itau_pdf(path, fallback_owner, start_date) do
    case System.cmd("pdftotext", ["-layout", path, "-"], stderr_to_stdout: true) do
      {text, 0} ->
        owner =
          case Regex.run(~r/^\s*([A-ZÁÉÍÓÚÂÊÔÃÕÇ ]{8,})\s+\d{3}\.\d{3}/m, text,
                 capture: :all_but_first
               ) do
            [name] -> clean_owner(name)
            _ -> fallback_owner
          end

        rows =
          text
          |> String.split("\n")
          |> Enum.flat_map(fn line ->
            case Regex.run(
                   ~r/^\s*(\d{2}\/\d{2}\/\d{4})\s+(.+?)\s+(-?[\d.]+,\d{2})(?:\s+(-?[\d.]+,\d{2}))?\s*$/,
                   line,
                   capture: :all_but_first
                 ) do
              [date, description, amount] ->
                pdf_row(date, description, amount, owner, line)

              [date, description, amount, _balance] ->
                pdf_row(date, description, amount, owner, line)

              _ ->
                []
            end
          end)

        filtered = filter_date(rows, start_date)
        {:ok, filtered, %{bank: "Itaú", owner: owner, ignored: length(rows) - length(filtered)}}

      {error, _} ->
        {:error, "pdftotext falhou: #{String.trim(error)}"}
    end
  rescue
    error in ErlangError -> {:error, "pdftotext não está instalado: #{Exception.message(error)}"}
  end

  defp pdf_row(date, description, amount, owner, raw_line) do
    description = String.trim(description)

    if String.contains?(description, "SALDO DO DIA") do
      []
    else
      [
        attrs(date_br(date), -money_to_cents(amount), description,
          bank: "Itaú",
          owner: owner,
          source_type: "conta",
          account_ref: "Conta Itaú 07146-5",
          raw_data: %{"linha" => String.trim(raw_line), "valor_original" => amount}
        )
      ]
    end
  end

  defp attrs(date, amount_cents, description, opts) do
    key = Classifier.merchant_key(description)
    source_type = Keyword.fetch!(opts, :source_type)
    flow_type = InternalTransfer.flow_type(description, amount_cents, source_type)
    {category, confidence, classifier} = classification(flow_type, description, key)

    %{
      occurred_on: date,
      amount_cents: amount_cents,
      description: description,
      merchant_key: key,
      flow_type: flow_type,
      category: category,
      classification_source: classifier,
      classification_confidence: confidence,
      review_status: "pending",
      bank: Keyword.fetch!(opts, :bank),
      owner: Keyword.fetch!(opts, :owner),
      account_ref: Keyword.get(opts, :account_ref),
      source_type: source_type,
      source_identifier: Keyword.get(opts, :source_identifier),
      raw_data: Keyword.get(opts, :raw_data, %{})
    }
  end

  defp classification("income", _description, _key), do: {"Outros", 0, "not_applicable"}
  defp classification(_flow_type, description, key), do: Classifier.classify(description, key)

  defp filter_date(rows, start_date),
    do: Enum.filter(rows, &(Date.compare(&1.occurred_on, start_date) != :lt))

  defp parse_csv_line(line), do: parse_csv_chars(String.to_charlist(line), [], [], false)

  defp parse_csv_chars([], field, fields, _quoted),
    do: Enum.reverse([field |> Enum.reverse() |> to_string() | fields])

  defp parse_csv_chars([?", ?" | rest], field, fields, true),
    do: parse_csv_chars(rest, [?" | field], fields, true)

  defp parse_csv_chars([?" | rest], field, fields, quoted),
    do: parse_csv_chars(rest, field, fields, not quoted)

  defp parse_csv_chars([?, | rest], field, fields, false),
    do: parse_csv_chars(rest, [], [field |> Enum.reverse() |> to_string() | fields], false)

  defp parse_csv_chars([char | rest], field, fields, quoted),
    do: parse_csv_chars(rest, [char | field], fields, quoted)

  defp money_to_cents(value) do
    value =
      value
      |> to_string()
      |> String.trim()
      |> String.replace(" ", "")
      |> String.replace(~r/[R$\s]/u, "")

    sign = if String.contains?(value, "-"), do: -1, else: 1
    absolute = String.replace(value, ~r/[^\d,.]/u, "")

    normalized =
      if String.contains?(absolute, ",") do
        absolute |> String.replace(".", "") |> String.replace(",", ".")
      else
        absolute
      end

    case String.split(normalized, ".") do
      [whole, cents] ->
        sign *
          (String.to_integer(empty_zero(whole)) * 100 +
             String.to_integer(String.pad_trailing(cents, 2, "0") |> String.slice(0, 2)))

      [whole] ->
        sign * String.to_integer(empty_zero(whole)) * 100
    end
  end

  defp empty_zero(""), do: "0"
  defp empty_zero(value), do: value

  defp date_br(value) do
    [day, month, year] =
      value |> String.trim() |> String.split("/") |> Enum.map(&String.to_integer/1)

    Date.new!(year, month, day)
  end

  defp zip_file(files, wanted) do
    case Enum.find(files, fn {name, _} -> to_string(name) == wanted end) do
      {_, content} -> {:ok, content}
      nil -> {:error, {:missing_file, wanted}}
    end
  end

  defp shared_strings(xml) do
    Regex.scan(~r/<si>(.*?)<\/si>/s, xml, capture: :all_but_first)
    |> Enum.map(fn [si] ->
      Regex.scan(~r/<t(?:\s[^>]*)?>(.*?)<\/t>/s, si, capture: :all_but_first)
      |> Enum.map_join(fn [text] -> xml_unescape(text) end)
    end)
  end

  defp decode_row(xml, shared) do
    Regex.scan(~r/<c\b([^>]*?)(?:\/>|>(.*?)<\/c>)/s, xml, capture: :all_but_first)
    |> Enum.reduce(%{}, fn captures, acc ->
      {cell_attrs, body} =
        case captures do
          [attrs, body] -> {attrs, body}
          [attrs] -> {attrs, ""}
        end

      ref = attr(cell_attrs, "r")
      column = ref && String.replace(ref, ~r/\d/, "")
      type = attr(cell_attrs, "t")

      value =
        case Regex.run(~r/<v>(.*?)<\/v>/s, body, capture: :all_but_first) do
          [v] -> v
          _ -> nil
        end

      decoded =
        cond do
          is_nil(value) -> nil
          type == "s" -> Enum.at(shared, String.to_integer(value))
          true -> value
        end

      if column, do: Map.put(acc, column, decoded), else: acc
    end)
  end

  defp attr(attrs, name) do
    case Regex.run(~r/(?:^|\s)#{name}="([^"]*)"/, attrs, capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end

  defp xml_unescape(value) do
    value
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp clean_owner(value) do
    cleaned =
      value
      |> to_string()
      |> String.trim()
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize(&1))

    cond do
      String.starts_with?(cleaned, "Thiago Carneiro Ribe") -> "Thiago Carneiro Ribeiral"
      String.starts_with?(cleaned, "Ana Clara De Paiva") -> "Ana Clara De Paiva"
      true -> cleaned
    end
  end
end
