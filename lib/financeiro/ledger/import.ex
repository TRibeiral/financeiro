defmodule Financeiro.Ledger.Import do
  use Ecto.Schema
  import Ecto.Changeset

  schema "imports" do
    field :filename, :string
    field :path, :string
    field :file_hash, :string
    field :bank, :string
    field :owner, :string
    field :status, :string, default: "completed"
    field :inserted_count, :integer, default: 0
    field :duplicate_count, :integer, default: 0
    field :ignored_count, :integer, default: 0
    field :error, :string

    has_many :transactions, Financeiro.Ledger.Transaction
    timestamps(type: :utc_datetime)
  end

  def changeset(import, attrs) do
    import
    |> cast(attrs, [
      :filename,
      :path,
      :file_hash,
      :bank,
      :owner,
      :status,
      :inserted_count,
      :duplicate_count,
      :ignored_count,
      :error
    ])
    |> validate_required([:filename, :path, :file_hash, :status])
    |> unique_constraint(:file_hash)
  end
end
