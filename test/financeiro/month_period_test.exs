defmodule Financeiro.MonthPeriodTest do
  use ExUnit.Case, async: true

  alias Financeiro.MonthPeriod

  test "runs an August period from August 5 through September 4" do
    assert MonthPeriod.bounds(~D[2026-08-05]) == {~D[2026-08-05], ~D[2026-09-04]}
    assert MonthPeriod.bounds(~D[2026-09-04]) == {~D[2026-08-05], ~D[2026-09-04]}
  end

  test "starts the September period on September 5" do
    assert MonthPeriod.bounds(~D[2026-09-05]) == {~D[2026-09-05], ~D[2026-10-04]}
  end

  test "handles a period across the year boundary" do
    assert MonthPeriod.bounds(~D[2027-01-02]) == {~D[2026-12-05], ~D[2027-01-04]}
  end
end
