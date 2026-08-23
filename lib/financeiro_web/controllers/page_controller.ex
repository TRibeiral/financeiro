defmodule FinanceiroWeb.PageController do
  use FinanceiroWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
