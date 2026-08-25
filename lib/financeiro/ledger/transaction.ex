defmodule Financeiro.Ledger.Transaction do
  use Ecto.Schema
  import Ecto.Changeset

  @categories ~w(Casa Funcionarios Mercado Restaurante Transporte Saude Extras Filho Viagem Pet Projetos Outros)
  @review_statuses ~w(pending reviewed)
  @flow_types ~w(expense refund income transfer excluded)

  schema "transactions" do
    field :occurred_on, :date
    field :amount_cents, :integer
    field :description, :string
    field :merchant_key, :string
    field :flow_type, :string, default: "expense"
    field :category, :string, default: "Outros"
    field :classification_source, :string, default: "automatic"
    field :classification_confidence, :integer, default: 0
    field :review_status, :string, default: "pending"
    field :previous_category, :string
    field :previous_review_status, :string
    field :previous_classification_source, :string
    field :previous_classification_confidence, :integer
    field :undo_action_id, :string
    field :bank, :string
    field :owner, :string
    field :account_ref, :string
    field :source_type, :string
    field :source_file, :string
    field :source_identifier, :string
    field :fingerprint, :string
    field :raw_data, :map, default: %{}

    belongs_to :import, Financeiro.Ledger.Import
    timestamps(type: :utc_datetime)
  end

  def categories, do: @categories

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :occurred_on,
      :amount_cents,
      :description,
      :merchant_key,
      :flow_type,
      :category,
      :classification_source,
      :classification_confidence,
      :review_status,
      :previous_category,
      :previous_review_status,
      :previous_classification_source,
      :previous_classification_confidence,
      :undo_action_id,
      :bank,
      :owner,
      :account_ref,
      :source_type,
      :source_file,
      :source_identifier,
      :fingerprint,
      :raw_data,
      :import_id
    ])
    |> validate_required([
      :occurred_on,
      :amount_cents,
      :description,
      :merchant_key,
      :flow_type,
      :category,
      :review_status,
      :bank,
      :owner,
      :source_type,
      :source_file,
      :fingerprint
    ])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:flow_type, @flow_types)
    |> validate_inclusion(:review_status, @review_statuses)
    |> validate_number(:classification_confidence,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 100
    )
    |> unique_constraint(:fingerprint)
  end
end
