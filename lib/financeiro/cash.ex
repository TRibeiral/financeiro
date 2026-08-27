defmodule Financeiro.Cash do
  import Ecto.Query

  alias Financeiro.Cash.Balance
  alias Financeiro.Repo

  def list_balances do
    Repo.all(from balance in Balance, order_by: [asc: balance.inserted_at, asc: balance.id])
  end

  def get_balance!(id), do: Repo.get!(Balance, id)

  def change_balance(%Balance{} = balance, attrs \\ %{}) do
    balance = %{balance | amount: Balance.amount_input(balance.amount_cents)}
    Balance.changeset(balance, attrs)
  end

  def create_balance(attrs) do
    %Balance{}
    |> Balance.changeset(attrs)
    |> Repo.insert()
  end

  def update_balance(%Balance{} = balance, attrs) do
    balance
    |> Balance.changeset(attrs)
    |> Repo.update()
  end

  def delete_balance(%Balance{} = balance), do: Repo.delete(balance)

  def summary(balances) do
    {positive, negative} =
      Enum.reduce(balances, {0, 0}, fn balance, {positive, negative} ->
        if balance.amount_cents >= 0 do
          {positive + balance.amount_cents, negative}
        else
          {positive, negative + balance.amount_cents}
        end
      end)

    %{
      total: positive + negative,
      positive: positive,
      negative: negative,
      count: length(balances)
    }
  end
end
