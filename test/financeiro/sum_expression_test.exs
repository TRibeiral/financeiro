defmodule Financeiro.SumExpressionTest do
  use ExUnit.Case, async: true

  alias Financeiro.SumExpression

  test "adds BRL values with Brazilian or dot decimals" do
    assert SumExpression.parse("2 + 440 + 59,90") == {:ok, 50_190}
    assert SumExpression.parse("R$ 1.200,50 + 25.25") == {:ok, 122_575}
    assert SumExpression.parse("500-125,50") == {:ok, 37_450}
  end

  test "treats an empty field as zero and rejects malformed expressions" do
    assert SumExpression.parse("") == {:ok, 0}
    assert SumExpression.parse("2++4") == :error
    assert SumExpression.parse("abc+20") == :error
  end
end
