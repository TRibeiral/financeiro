defmodule FinanceiroWeb.PageControllerTest do
  use FinanceiroWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Despesas"
    assert html_response(conn, 200) =~ "Compras e estornos"
  end
end
