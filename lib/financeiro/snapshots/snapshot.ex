defmodule Financeiro.Snapshots.Snapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias Financeiro.Snapshots.Item

  schema "net_worth_snapshots" do
    field :captured_at, :utc_datetime
    field :total_cents, :integer
    field :cash_cents, :integer
    field :stocks_cents, :integer
    field :other_investments_cents, :integer
    field :cash_count, :integer, default: 0
    field :stocks_count, :integer, default: 0
    field :other_investments_count, :integer, default: 0
    field :stocks_without_quote_count, :integer, default: 0

    has_many :items, Item

    timestamps(type: :utc_datetime)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :captured_at,
      :total_cents,
      :cash_cents,
      :stocks_cents,
      :other_investments_cents,
      :cash_count,
      :stocks_count,
      :other_investments_count,
      :stocks_without_quote_count
    ])
    |> validate_required([
      :captured_at,
      :total_cents,
      :cash_cents,
      :stocks_cents,
      :other_investments_cents
    ])
  end
end
