defmodule Financeiro.CashFlow.Month do
  use Ecto.Schema
  import Ecto.Changeset

  alias Financeiro.SumExpression

  schema "cash_flow_months" do
    field :period_start, :date
    field :investment_income_expression, :string, default: ""
    field :investment_income_cents, :integer, default: 0
    field :capex_expression, :string, default: ""
    field :capex_cents, :integer, default: 0
    field :available_cents, :integer
    field :obligations_cents, :integer
    field :cash_synced_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(month, attrs) do
    attrs = stringify_keys(attrs)

    {attrs, expression_errors} =
      attrs
      |> normalize_expression("investment_income_expression", "investment_income_cents")
      |> normalize_expression("capex_expression", "capex_cents")

    month
    |> cast(attrs, [
      :period_start,
      :investment_income_expression,
      :investment_income_cents,
      :capex_expression,
      :capex_cents,
      :available_cents,
      :obligations_cents,
      :cash_synced_at
    ])
    |> validate_required([:period_start, :investment_income_cents, :capex_cents])
    |> unique_constraint(:period_start)
    |> add_expression_errors(expression_errors)
  end

  defp normalize_expression({attrs, errors}, expression_key, cents_key) do
    case Map.fetch(attrs, expression_key) do
      {:ok, expression} ->
        case SumExpression.parse(expression) do
          {:ok, cents} ->
            {attrs
             |> Map.put(expression_key, String.trim(expression))
             |> Map.put(cents_key, cents), errors}

          :error ->
            {Map.delete(attrs, cents_key), [String.to_existing_atom(expression_key) | errors]}
        end

      :error ->
        {attrs, errors}
    end
  end

  defp normalize_expression(attrs, expression_key, cents_key),
    do: normalize_expression({attrs, []}, expression_key, cents_key)

  defp add_expression_errors(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      add_error(changeset, field, "use valores separados por +, como 120+35,90")
    end)
  end

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
