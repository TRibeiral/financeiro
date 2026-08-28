defmodule Financeiro.Cash.Balance do
  use Ecto.Schema
  import Ecto.Changeset

  alias Financeiro.MoneyInput

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

  def amount_input(cents), do: MoneyInput.format(cents)

  defp normalize_amount(%{"amount" => amount} = attrs, _balance) do
    case MoneyInput.parse(amount) do
      {:ok, cents} -> {Map.put(attrs, "amount_cents", cents), nil}
      :error -> {Map.delete(attrs, "amount_cents"), "use um valor como 1250,00 ou -450,90"}
    end
  end

  defp normalize_amount(%{"amount_cents" => amount_cents} = attrs, _balance)
       when amount_cents not in [nil, ""],
       do: {attrs, nil}

  defp normalize_amount(attrs, %{amount_cents: amount_cents}) when is_integer(amount_cents),
    do: {attrs, nil}

  defp normalize_amount(attrs, _balance), do: {attrs, "informe o saldo"}

  defp maybe_add_amount_error(changeset, nil), do: changeset

  defp maybe_add_amount_error(changeset, message),
    do: add_error(changeset, :amount, message)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
