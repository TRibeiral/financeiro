defmodule Financeiro.Investments.Stock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "stocks" do
    field :name, :string
    field :ticker, :string
    field :shares, :integer, default: 0
    field :quote_cents, :integer
    field :last_result, :string, default: "2T26"
    field :tier, :integer, default: 0
    field :checked_on, :date
    field :purchase_heat, :integer, default: 0
    field :quote_refreshed_at, :utc_datetime
    field :quote_source, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(stock, attrs) do
    stock
    |> cast(attrs, [:name, :ticker, :shares, :last_result, :tier, :checked_on])
    |> update_change(:name, &String.trim/1)
    |> update_change(:ticker, &normalize_ticker/1)
    |> update_change(:last_result, &normalize_result/1)
    |> validate_required([:name, :ticker, :shares, :last_result, :tier])
    |> validate_number(:shares, greater_than_or_equal_to: 0)
    |> validate_number(:tier, greater_than_or_equal_to: -1, less_than_or_equal_to: 5)
    |> validate_format(:ticker, ~r/^[A-Z0-9]{4,10}$/, message: "use o código da B3, como PETR4")
    |> validate_format(:last_result, ~r/^[1-4]T\d{2}$/, message: "use o formato 2T26")
    |> unique_constraint(:ticker)
  end

  defp normalize_ticker(value),
    do: value |> String.trim() |> String.upcase() |> String.replace(".SA", "")

  defp normalize_result(value) do
    value
    |> String.trim()
    |> String.upcase()
    |> String.replace("/", "T")
  end
end
