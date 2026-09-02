defmodule Financeiro.SumExpression do
  @moduledoc "Parses simple sums of BRL values, such as `2+440+59,90`."

  alias Financeiro.MoneyInput

  def parse(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.replace("R$", "")
      |> String.replace(~r/\s/u, "")
      |> String.replace("−", "-")

    cond do
      normalized == "" ->
        {:ok, 0}

      true ->
        terms = Regex.scan(~r/[+-]?[^+-]+/, normalized) |> List.flatten()

        if Enum.join(terms) == normalized do
          sum_terms(terms)
        else
          :error
        end
    end
  end

  def parse(_value), do: :error

  defp sum_terms(terms) do
    Enum.reduce_while(terms, {:ok, 0}, fn term, {:ok, total} ->
      case MoneyInput.parse(term) do
        {:ok, cents} -> {:cont, {:ok, total + cents}}
        :error -> {:halt, :error}
      end
    end)
  end
end
