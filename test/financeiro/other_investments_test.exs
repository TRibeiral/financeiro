defmodule Financeiro.OtherInvestmentsTest do
  use Financeiro.DataCase

  alias Financeiro.Investments

  test "stores and summarizes other investments" do
    assert {:ok, treasury} =
             Investments.create_other_investment(%{
               description: "Tesouro Direto",
               value: "12.345,67"
             })

    assert treasury.value_cents == 1_234_567

    assert {:ok, fund} =
             Investments.create_other_investment(%{description: "Fundo", value: "500.25"})

    assert Investments.other_investments_summary(Investments.list_other_investments()) == %{
             total: 1_284_592,
             count: 2
           }

    assert {:ok, updated} =
             Investments.update_other_investment(fund, %{
               description: "Fundo atualizado",
               value: "750"
             })

    assert updated.description == "Fundo atualizado"
    assert updated.value_cents == 75_000
  end

  test "rejects zero, negative, and malformed values" do
    for value <- ["0", "-10", "abc"] do
      assert {:error, changeset} =
               Investments.create_other_investment(%{description: "Inválido", value: value})

      assert errors_on(changeset).value != []
    end
  end
end
