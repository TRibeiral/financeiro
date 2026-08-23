defmodule FinanceiroWeb.ErrorJSONTest do
  use FinanceiroWeb.ConnCase, async: true

  test "renders 404" do
    assert FinanceiroWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert FinanceiroWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
