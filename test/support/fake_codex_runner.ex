defmodule Financeiro.FakeCodexRunner do
  def run(prompt, _opts) do
    classifications =
      Regex.scan(~r/\"id\":(\d+)/, prompt, capture: :all_but_first)
      |> Enum.map(fn [id] ->
        %{"id" => String.to_integer(id), "category" => "Mercado", "confidence" => 91}
      end)

    {:ok, classifications}
  end
end
