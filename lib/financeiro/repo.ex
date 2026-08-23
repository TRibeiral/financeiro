defmodule Financeiro.Repo do
  use Ecto.Repo,
    otp_app: :financeiro,
    adapter: Ecto.Adapters.SQLite3
end
