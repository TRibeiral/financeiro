defmodule Financeiro.CodexRunner do
  @moduledoc "Runs constrained, non-interactive Codex tasks using ChatGPT sign-in."

  @model "gpt-5.6-luna"

  def run(prompt, opts \\ []) do
    codex = Application.get_env(:financeiro, :codex_executable, "codex")
    timeout_seconds = Keyword.get(opts, :timeout_seconds, 180)

    schema =
      Keyword.get(
        opts,
        :output_schema,
        Application.app_dir(:financeiro, "priv/luna_classification.schema.json")
      )

    output_key = Keyword.get(opts, :output_key, "classifications")

    output =
      Path.join(System.tmp_dir!(), "financeiro-luna-#{System.unique_integer([:positive])}.json")

    args =
      [
        "exec",
        "--model",
        @model,
        "--sandbox",
        "read-only",
        "--ephemeral",
        "--ignore-user-config",
        "--skip-git-repo-check",
        "--color",
        "never",
        "--output-schema",
        schema,
        "--output-last-message",
        output,
        "-c",
        ~s(forced_login_method="chatgpt"),
        "-C",
        System.tmp_dir!(),
        prompt
      ]
      |> maybe_enable_web_search(Keyword.get(opts, :web_search, false))

    try do
      {command, command_args} = timeout_command(codex, args, timeout_seconds)
      shell = System.find_executable("sh") || "/bin/sh"

      case System.cmd(
             shell,
             ["-c", ~s(exec "$@" </dev/null), "financeiro-codex", command | command_args],
             stderr_to_stdout: true,
             env: [{"OPENAI_API_KEY", nil}],
             into: ""
           ) do
        {_log, 0} -> decode_output(output, output_key)
        {log, status} -> {:error, "Codex Luna terminou com status #{status}: #{compact(log)}"}
      end
    rescue
      error in ErlangError ->
        {:error, "não foi possível executar o Codex CLI: #{Exception.message(error)}"}
    after
      File.rm(output)
    end
  end

  def model, do: @model

  # --search is a global Codex option and must appear before the `exec` subcommand.
  defp maybe_enable_web_search(args, true), do: ["--search" | args]
  defp maybe_enable_web_search(args, false), do: args

  defp timeout_command(codex, args, seconds) do
    case System.find_executable("timeout") do
      nil -> {codex, args}
      timeout -> {timeout, ["#{seconds}s", codex | args]}
    end
  end

  defp decode_output(path, output_key) do
    with {:ok, body} <- File.read(path),
         {:ok, decoded} <- Jason.decode(body),
         results when is_list(results) <- decoded[output_key] do
      {:ok, results}
    else
      {:error, reason} -> {:error, "resposta Luna inválida: #{inspect(reason)}"}
      _ -> {:error, "resposta Luna não contém #{output_key}"}
    end
  end

  defp compact(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 500)
  end
end
