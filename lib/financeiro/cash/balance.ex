defmodule Financeiro.Cash.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cash_balances" do
    field :name, :string
    field :amount_cents, :integer
    field :amount, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(balance, attrs) do
    attrs = stringify_keys(attrs)
    {attrs, amount_error} = normalize_amount(attrs, balance)

    balance
    |> cast(attrs, [:name, :amount, :amount_cents])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> maybe_add_amount_error(amount_error)
  end

  def amount_input(nil), do: nil

  def amount_input(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    absolute = abs(cents)

    "#{sign}#{div(absolute, 100)}.#{absolute |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp normalize_amount(%{"amount" => amount} = attrs, _balance) do
    case parse_amount(amount) do
      {:ok, cents} -> {Map.put(attrs, "amount_cents", cents), nil}
      {:error, message} -> {Map.delete(attrs, "amount_cents"), message}
    end
  end

  defp normalize_amount(%{"amount_cents" => amount_cents} = attrs, _balance)
       when amount_cents not in [nil, ""],
       do: {attrs, nil}

  defp normalize_amount(attrs, %{amount_cents: amount_cents}) when is_integer(amount_cents),
    do: {attrs, nil}

  defp normalize_amount(attrs, _balance), do: {attrs, "informe o saldo"}

  defp parse_amount(amount) when is_integer(amount), do: {:ok, amount * 100}

  defp parse_amount(amount) when is_binary(amount) do
    normalized =
      amount
      |> String.trim()
      |> String.replace("R$", "")
      |> String.replace(" ", "")
      |> String.replace("−", "-")
      |> normalize_separators()

    case Regex.run(~r/^([+-]?)(\d+)(?:\.(\d{1,2}))?$/, normalized) do
      [_, sign, whole] -> {:ok, signed_cents(sign, whole, "")}
      [_, sign, whole, decimals] -> {:ok, signed_cents(sign, whole, decimals)}
      _ -> {:error, "use um valor como 1250,00 ou -450,90"}
    end
  end

  defp parse_amount(_amount), do: {:error, "informe um saldo válido"}

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

  defp maybe_add_amount_error(changeset, nil), do: changeset

  defp maybe_add_amount_error(changeset, message),
    do: add_error(changeset, :amount, message)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
