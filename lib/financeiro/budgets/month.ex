defmodule Financeiro.Budgets.Month do
  use Ecto.Schema
  import Ecto.Changeset

  schema "budget_months" do
    field :period_start, :date
    field :amount_cents, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(month, attrs) do
    month
    |> cast(attrs, [:period_start, :amount_cents])
    |> validate_required([:period_start, :amount_cents])
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> validate_period_start()
    |> unique_constraint(:period_start)
  end

  defp validate_period_start(changeset) do
    validate_change(changeset, :period_start, fn :period_start, date ->
      if date.day == 5, do: [], else: [period_start: "must be the start of a financial month"]
    end)
  end
end
