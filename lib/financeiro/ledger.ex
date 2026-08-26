defmodule Financeiro.Ledger do
  import Ecto.Query
  alias Financeiro.MonthPeriod
  alias Financeiro.Repo
  alias Financeiro.Ledger.{Import, Transaction}

  def categories, do: Transaction.categories()

  def list_transactions(filters \\ %{}) do
    Transaction
    |> where([t], t.flow_type in ["expense", "refund"])
    |> filter_query(filters)
    |> order_transactions(Map.get(filters, "sort"))
    |> limit(500)
    |> Repo.all()
  end

  def get_transaction!(id), do: Repo.get!(Transaction, id)

  def next_pending do
    Repo.one(
      from t in Transaction,
        where: t.review_status == "pending" and t.flow_type in ["expense", "refund"],
        order_by: [desc: t.occurred_on, desc: t.id],
        limit: 1
    )
  end

  def pending_count,
    do:
      Repo.aggregate(
        from(t in Transaction,
          where: t.review_status == "pending" and t.flow_type in ["expense", "refund"]
        ),
        :count
      )

  def transaction_count,
    do:
      Repo.aggregate(
        from(t in Transaction, where: t.flow_type in ["expense", "refund"]),
        :count
      )

  def update_transaction(%Transaction{} = transaction, attrs) do
    transaction |> Transaction.changeset(attrs) |> Repo.update()
  end

  def review_transaction(transaction, category, action_id \\ Ecto.UUID.generate()) do
    transaction
    |> snapshot_attrs(action_id)
    |> Map.merge(%{
      category: category,
      review_status: "reviewed",
      classification_source: "manual",
      classification_confidence: 100
    })
    |> then(&update_transaction(transaction, &1))
  end

  def change_category(transaction, category, action_id \\ Ecto.UUID.generate()) do
    transaction
    |> snapshot_attrs(action_id)
    |> Map.merge(%{
      category: category,
      classification_source: "manual",
      classification_confidence: 100
    })
    |> then(&update_transaction(transaction, &1))
  end

  def reopen_transaction(transaction, action_id \\ Ecto.UUID.generate()) do
    transaction
    |> snapshot_attrs(action_id)
    |> Map.put(:review_status, "pending")
    |> then(&update_transaction(transaction, &1))
  end

  def review_similar(transaction, category) do
    transactions =
      Repo.all(
        from(t in Transaction,
          where:
            t.merchant_key == ^transaction.merchant_key and t.review_status == "pending" and
              t.flow_type in ["expense", "refund"]
        )
      )

    action_id = Ecto.UUID.generate()

    Repo.transaction(fn ->
      Enum.each(transactions, fn candidate ->
        {:ok, _} = review_transaction(candidate, category, action_id)
      end)
    end)

    length(transactions)
  end

  def latest_undo_action do
    Repo.one(
      from t in Transaction,
        where: not is_nil(t.undo_action_id),
        order_by: [desc: t.updated_at, desc: t.id],
        limit: 1,
        select: t.undo_action_id
    )
  end

  def undo_transaction(%Transaction{undo_action_id: action_id}), do: undo_action(action_id)

  def undo_action(nil), do: {:ok, 0}

  def undo_action(action_id) do
    transactions = Repo.all(from t in Transaction, where: t.undo_action_id == ^action_id)

    Repo.transaction(fn ->
      Enum.each(transactions, fn transaction ->
        {:ok, _} =
          update_transaction(transaction, %{
            category: transaction.previous_category,
            review_status: transaction.previous_review_status,
            classification_source: transaction.previous_classification_source,
            classification_confidence: transaction.previous_classification_confidence,
            previous_category: nil,
            previous_review_status: nil,
            previous_classification_source: nil,
            previous_classification_confidence: nil,
            undo_action_id: nil
          })
      end)

      length(transactions)
    end)
  end

  defp snapshot_attrs(transaction, action_id) do
    %{
      previous_category: transaction.category,
      previous_review_status: transaction.review_status,
      previous_classification_source: transaction.classification_source,
      previous_classification_confidence: transaction.classification_confidence,
      undo_action_id: action_id
    }
  end

  def list_imports, do: Repo.all(from i in Import, order_by: [desc: i.inserted_at], limit: 50)

  def list_review_queue do
    Repo.all(
      from t in Transaction,
        where: t.review_status == "pending" and t.flow_type in ["expense", "refund"],
        order_by: [desc: t.occurred_on, desc: t.id],
        limit: 500
    )
  end

  def list_income(filters \\ %{}) do
    Transaction
    |> where([t], t.flow_type == "income")
    |> filter_query(filters)
    |> order_by([t], desc: t.occurred_on, desc: t.id)
    |> limit(500)
    |> Repo.all()
  end

  def income_totals(filters \\ MonthPeriod.filters()) do
    income_query =
      Transaction
      |> where([t], t.flow_type == "income")
      |> filter_query(filters)

    %{
      total:
        Repo.one(from t in income_query, select: coalesce(sum(t.amount_cents), 0))
        |> abs(),
      count: Repo.aggregate(income_query, :count)
    }
  end

  def income_filter_options do
    income = from t in Transaction, where: t.flow_type == "income"

    %{
      owners: Repo.all(from t in income, distinct: true, order_by: t.owner, select: t.owner),
      banks: Repo.all(from t in income, distinct: true, order_by: t.bank, select: t.bank),
      sources:
        Repo.all(
          from t in income,
            distinct: true,
            order_by: t.source_type,
            select: t.source_type
        )
    }
  end

  def totals(filters \\ MonthPeriod.filters()) do
    expense_query =
      Transaction
      |> where([t], t.flow_type in ["expense", "refund"])
      |> filter_query(filters)

    %{
      expenses: Repo.one(from t in expense_query, select: coalesce(sum(t.amount_cents), 0)),
      count: Repo.aggregate(expense_query, :count),
      pending: Repo.aggregate(where(expense_query, [t], t.review_status == "pending"), :count)
    }
  end

  def spending_by(field) when field in [:category, :owner, :bank] do
    {from_date, to_date} = MonthPeriod.current_bounds()
    spending_by(field, from_date, to_date)
  end

  def spending_by(field, %Date{} = from_date, %Date{} = to_date)
      when field in [:category, :owner, :bank] do
    from(t in Transaction,
      where:
        t.flow_type in ["expense", "refund"] and t.occurred_on >= ^from_date and
          t.occurred_on <= ^to_date,
      group_by: field(t, ^field),
      select: {field(t, ^field), sum(t.amount_cents)},
      order_by: [desc: sum(t.amount_cents)]
    )
    |> Repo.all()
  end

  def spending_by_category_between(%Date{} = from_date, %Date{} = to_date) do
    Repo.all(
      from t in Transaction,
        where:
          t.flow_type in ["expense", "refund"] and t.occurred_on >= ^from_date and
            t.occurred_on <= ^to_date,
        group_by: t.category,
        select: {t.category, sum(t.amount_cents)},
        order_by: [desc: sum(t.amount_cents)]
    )
  end

  def spending_by_day do
    {from_date, to_date} = MonthPeriod.current_bounds()
    spending_by_day(from_date, to_date)
  end

  def spending_by_day(%Date{} = from_date, %Date{} = to_date) do
    Repo.all(
      from t in Transaction,
        where:
          t.flow_type in ["expense", "refund"] and t.occurred_on >= ^from_date and
            t.occurred_on <= ^to_date,
        group_by: t.occurred_on,
        select: {t.occurred_on, sum(t.amount_cents)},
        order_by: t.occurred_on
    )
  end

  def spending_by_day_and_category do
    {from_date, to_date} = MonthPeriod.current_bounds()
    spending_by_day_and_category(from_date, to_date)
  end

  def spending_by_day_and_category(%Date{} = from_date, %Date{} = to_date) do
    Repo.all(
      from t in Transaction,
        where:
          t.flow_type in ["expense", "refund"] and t.occurred_on >= ^from_date and
            t.occurred_on <= ^to_date,
        group_by: [t.occurred_on, t.category, t.flow_type],
        select: {t.occurred_on, t.category, t.flow_type, sum(t.amount_cents)},
        order_by: [asc: t.occurred_on, asc: t.category, asc: t.flow_type]
    )
  end

  def filter_options do
    expenses = from t in Transaction, where: t.flow_type in ["expense", "refund"]

    %{
      owners: Repo.all(from t in expenses, distinct: true, order_by: t.owner, select: t.owner),
      banks: Repo.all(from t in expenses, distinct: true, order_by: t.bank, select: t.bank),
      sources:
        Repo.all(
          from t in expenses,
            distinct: true,
            order_by: t.source_type,
            select: t.source_type
        )
    }
  end

  defp filter_query(query, filters) do
    Enum.reduce(filters, query, fn
      {_key, value}, query when value in [nil, "", "all"] ->
        query

      {"search", value}, query ->
        where(query, [t], like(t.description, ^"%#{value}%"))

      {"category", value}, query ->
        where(query, [t], t.category == ^value)

      {"owner", value}, query ->
        where(query, [t], t.owner == ^value)

      {"bank", value}, query ->
        where(query, [t], t.bank == ^value)

      {"origin", "transfer"}, query ->
        where(query, [t], t.flow_type == "transfer")

      {"origin", value}, query ->
        where(query, [t], t.source_type == ^value)

      {"status", value}, query ->
        where(query, [t], t.review_status == ^value)

      {"direction", "expenses"}, query ->
        where(query, [t], t.flow_type == "expense")

      {"direction", "refunds"}, query ->
        where(query, [t], t.flow_type == "refund")

      {"direction", "spending"}, query ->
        where(query, [t], t.flow_type in ["expense", "refund"])

      {"direction", "credits"}, query ->
        where(query, [t], t.flow_type == "income")

      {"direction", "transfers"}, query ->
        where(query, [t], t.flow_type == "transfer")

      {"direction", "without_transfers"}, query ->
        where(query, [t], t.flow_type in ["expense", "refund"])

      {"direction", "excluded"}, query ->
        where(query, [t], t.flow_type == "excluded")

      {"from", value}, query ->
        case Date.from_iso8601(value) do
          {:ok, date} -> where(query, [t], t.occurred_on >= ^date)
          _ -> query
        end

      {"to", value}, query ->
        case Date.from_iso8601(value) do
          {:ok, date} -> where(query, [t], t.occurred_on <= ^date)
          _ -> query
        end

      _, query ->
        query
    end)
  end

  defp order_transactions(query, "date_asc"),
    do: order_by(query, [t], asc: t.occurred_on, asc: t.id)

  defp order_transactions(query, "value_desc"),
    do: order_by(query, [t], desc: t.amount_cents, desc: t.occurred_on, desc: t.id)

  defp order_transactions(query, "value_asc"),
    do: order_by(query, [t], asc: t.amount_cents, desc: t.occurred_on, desc: t.id)

  defp order_transactions(query, _date_desc),
    do: order_by(query, [t], desc: t.occurred_on, desc: t.id)
end
