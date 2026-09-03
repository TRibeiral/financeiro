defmodule Financeiro.Snapshots.Item do
  use Ecto.Schema

  alias Financeiro.Snapshots.Snapshot

  schema "net_worth_snapshot_items" do
    field :category, :string
    field :name, :string
    field :value_cents, :integer
    field :source_id, :integer
    field :ticker, :string
    field :shares, :integer
    field :quote_cents, :integer

    belongs_to :snapshot, Snapshot

    timestamps(type: :utc_datetime)
  end
end
