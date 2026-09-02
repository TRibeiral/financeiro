defmodule Financeiro.FakeCodexRunner do
  def run(prompt, opts) do
    if Keyword.get(opts, :output_key) == "alerts" do
      ids = Regex.scan(~r/"transaction":\{[^}]*"id":(\d+)/, prompt, capture: :all_but_first)

      {:ok,
       Enum.map(ids, fn [id] ->
         %{
           "id" => String.to_integer(id),
           "possible_changed_transaction" => false,
           "candidate_id" => nil,
           "confidence" => 90,
           "reason" => "Nenhuma versão anterior provável"
         }
       end)}
    else
      classify(prompt)
    end
  end

  defp classify(prompt) do
    classifications =
      Regex.scan(~r/\"id\":(\d+)/, prompt, capture: :all_but_first)
      |> Enum.map(fn [id] ->
        %{"id" => String.to_integer(id), "category" => "Mercado", "confidence" => 91}
      end)

    {:ok, classifications}
  end
end
