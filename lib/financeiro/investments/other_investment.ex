defmodule Financeiro.Investments.OtherInvestment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Financeiro.MoneyInput

  schema "other_investments" do
    field :description, :string
    field :value_cents, :integer
    field :value, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def changeset(investment, attrs) do
    attrs = stringify_keys(attrs)
    {attrs, value_error} = normalize_value(attrs, investment)

    investment
    |> cast(attrs, [:description, :value, :value_cents])
    |> update_change(:description, &String.trim/1)
    |> validate_required([:description])
    |> validate_length(:description, max: 120)
    |> validate_number(:value_cents, greater_than: 0)
    |> maybe_add_value_error(value_error)
  end

  def value_input(cents), do: MoneyInput.format(cents)

  defp normalize_value(%{"value" => value} = attrs, _investment) do
    case MoneyInput.parse(value) do
      {:ok, cents} when cents > 0 -> {Map.put(attrs, "value_cents", cents), nil}
      {:ok, cents} -> {Map.put(attrs, "value_cents", cents), "deve ser maior que zero"}
      :error -> {Map.delete(attrs, "value_cents"), "use um valor como 1250,00"}
    end
  end

  defp normalize_value(%{"value_cents" => value_cents} = attrs, _investment)
       when value_cents not in [nil, ""],
       do: {attrs, nil}

  defp normalize_value(attrs, %{value_cents: value_cents}) when is_integer(value_cents),
    do: {attrs, nil}

  defp normalize_value(attrs, _investment), do: {attrs, "informe o valor"}

  defp maybe_add_value_error(changeset, nil), do: changeset
  defp maybe_add_value_error(changeset, message), do: add_error(changeset, :value, message)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
