defmodule Financeiro.MoneyInput do
  @moduledoc false

  def parse(value) when is_integer(value), do: {:ok, value * 100}

  def parse(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.replace("R$", "")
      |> String.replace(" ", "")
      |> String.replace("−", "-")
      |> normalize_separators()

    case Regex.run(~r/^([+-]?)(\d+)(?:\.(\d{1,2}))?$/, normalized) do
      [_, sign, whole] -> {:ok, signed_cents(sign, whole, "")}
      [_, sign, whole, decimals] -> {:ok, signed_cents(sign, whole, decimals)}
      _ -> :error
    end
  end

  def parse(_value), do: :error

  def format(nil), do: nil

  def format(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    absolute = abs(cents)

    "#{sign}#{div(absolute, 100)}.#{absolute |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp normalize_separators(value) do
    if String.contains?(value, ",") do
      value |> String.replace(".", "") |> String.replace(",", ".")
    else
      value
    end
  end

  defp signed_cents(sign, whole, decimals) do
    cents =
      String.to_integer(whole) * 100 +
        (decimals |> String.pad_trailing(2, "0") |> String.to_integer())

    if sign == "-", do: -cents, else: cents
  end
end
