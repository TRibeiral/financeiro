# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Financeiro.Repo.insert!(%Financeiro.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Financeiro.Investments.Stock
alias Financeiro.Repo

# Initial B3 portfolio imported from the user's August 2026 tracker. Keeping this
# idempotent makes `mix ecto.setup` useful without overwriting later manual edits.
stocks = [
  %{name: "PRIO", ticker: "PRIO3", shares: 7_200, tier: 5, checked_on: ~D[2026-05-05]},
  %{name: "3tentos", ticker: "TTEN3", shares: 21_100, tier: 4, checked_on: ~D[2026-08-15]},
  %{name: "Petrobras", ticker: "PETR4", shares: 6_200, tier: 3, checked_on: ~D[2026-08-08]},
  %{name: "Bemobi", ticker: "BMOB3", shares: 8_300, tier: 3, checked_on: ~D[2026-08-14]},
  %{name: "Porto", ticker: "PSSA3", shares: 4_000, tier: 2, checked_on: ~D[2026-08-08]},
  %{name: "Smart Fit", ticker: "SMFT3", shares: 10_400, tier: 3, checked_on: ~D[2026-08-08]},
  %{
    name: "Totvs",
    ticker: "TOTS3",
    shares: 4_800,
    tier: 4,
    checked_on: ~D[2026-08-08],
    purchase_heat: 5
  },
  %{name: "Unifique", ticker: "FIQE3", shares: 33_600, tier: 2, checked_on: ~D[2026-08-14]},
  %{name: "Estapar", ticker: "ALPK3", shares: 23_000, tier: 2, checked_on: ~D[2026-08-08]},
  %{name: "Multiplan", ticker: "MULT3", shares: 3_500, tier: 3, checked_on: ~D[2026-08-03]},
  %{
    name: "Movida",
    ticker: "MOVI3",
    shares: 12_900,
    tier: 3,
    checked_on: ~D[2026-08-13],
    purchase_heat: 3
  },
  %{
    name: "Track&Field",
    ticker: "TFCO4",
    shares: 7_100,
    tier: 3,
    checked_on: ~D[2026-08-15],
    purchase_heat: 1
  },
  %{name: "Direcional", ticker: "DIRR3", shares: 7_400, tier: 2, checked_on: ~D[2026-08-15]},
  %{name: "CSU Digital", ticker: "CSUD3", shares: 6_200, tier: 2, checked_on: ~D[2026-08-14]},
  %{
    name: "Aura Minerals",
    ticker: "AURA33",
    shares: 325,
    tier: 2,
    checked_on: ~D[2026-08-10]
  },
  %{
    name: "JHSF",
    ticker: "JHSF3",
    shares: 3_200,
    tier: 3,
    checked_on: ~D[2026-08-18],
    purchase_heat: 4
  }
]

Enum.each(stocks, fn attrs ->
  %Stock{}
  |> Stock.changeset(Map.put(attrs, :last_result, "2T26"))
  |> Ecto.Changeset.put_change(:purchase_heat, Map.get(attrs, :purchase_heat, 0))
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :ticker)
end)
