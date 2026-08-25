# Financeiro

Aplicação pessoal e local para consolidar extratos, classificar despesas e revisar categorias.

## Rodar

```bash
mix setup
mix phx.server
```

Abra [http://localhost:4000](http://localhost:4000). O SQLite fica em `financeiro_dev.db`.

No ambiente de desenvolvimento, a pasta `../extratos` é verificada a cada 15 segundos. Também é possível importar explicitamente:

Na tela **Importações**, arquivos CSV, XLSX e PDF podem ser soltos diretamente na área de upload. Eles são copiados com segurança para a pasta monitorada e importados automaticamente; arquivos existentes não são sobrescritos.

```bash
mix financeiro.import ../extratos
mix financeiro.import /caminho/arquivo.csv --owner "Ana Clara"
```

O classificador exige o Codex CLI autenticado pela assinatura do ChatGPT:

```bash
codex login status
mix financeiro.classify
```

O primeiro comando deve mostrar `Logged in using ChatGPT`. Não é usada uma chave de API.

Formatos reconhecidos:

- CSV de conta e cartão Nubank;
- XLSX de fatura Itaú (o titular é lido em cada lançamento);
- PDF de conta Itaú, usando o utilitário local `pdftotext`.

Só entram lançamentos a partir de `2026-08-01`. Cada arquivo tem um hash e cada lançamento tem uma impressão digital estável baseada na origem, data, valor, descrição, pessoa e conta/cartão. Isso permite sobrepor períodos sem repetir dados.

## Classificação

As categorias são `Casa`, `Funcionarios`, `Mercado`, `Restaurante`, `Transporte`, `Saude`, `Extras`, `Filho`, `Viagem`, `Pet`, `Projetos` e `Outros`.

O classificador funciona em três camadas:

1. reutiliza decisões já revisadas para o mesmo estabelecimento;
2. aplica regras locais como contexto preliminar;
3. envia os lançamentos ainda sem histórico, em lotes, ao `gpt-5.6-luna` usando `codex exec` e a sessão local da assinatura do ChatGPT.

Toda classificação automática começa como pendente. Trocar a categoria na tabela salva a nova categoria imediatamente, mas não confirma implicitamente um lançamento pendente. A tela **Revisar** permite confirmar, corrigir ou aplicar uma decisão a todos os lançamentos semelhantes. Assim, o histórico manual passa a ter prioridade nas próximas importações.

Cada confirmação guarda persistentemente o estado anterior. O botão **Desfazer última** restaura a ação global mais recente. Em cada linha há uma única ação contextual: ✓ confirma um pendente; ↶ desfaz a última alteração de um revisado ou reabre uma confirmação antiga sem histórico. Uma confirmação de semelhantes é desfeita como um único grupo, mesmo depois de navegar ou atualizar a página.

O passe Luna acontece automaticamente após cada importação. Se o Codex estiver temporariamente indisponível, os itens ficam marcados como `luna_error` e podem ser retomados pelo botão **Luna** na tela de importações ou por `mix financeiro.classify`. A execução é efêmera, usa sandbox somente leitura e força autenticação ChatGPT; não faz chamadas diretas à API.

Recebimentos reais, como salários e depósitos, aparecem exclusivamente na aba **Entradas**. Eles não recebem categoria, não entram na fila de revisão e não fazem parte das despesas ou das análises de gastos.

Estornos e reembolsos continuam na aba **Despesas**, recebem a categoria da compra correspondente e são somados com valor negativo. Assim, o total de **Saídas líquidas** já representa despesas menos estornos, sem apresentar um total de estornos separado.

Na aba **Análises**, o **Panorama** reúne o realizado e a projeção de fechamento do mês por categoria e no total. O cálculo usa o gasto líquido do primeiro dia até hoje, divide pelos dias corridos e multiplica pela quantidade de dias do mês; a data corrente segue o horário de São Paulo. A visão **Ritmo** empilha cada dia nas cores das categorias e marca estornos com hachura.

Transferências entre as contas de Thiago, transferências entre Thiago e Ana Clara, pagamentos de fatura e movimentos internos de investimento são preservados na base como `transfer`, mas nunca aparecem em **Despesas** nem entram na fila de revisão, totais ou gráficos.

Créditos genéricos, dividendos/JSCP, rendimentos automáticos e operações ou impostos ligados à B3 são preservados como `excluded`, mas também nunca aparecem em **Despesas** nem entram em qualquer total ou gráfico de gastos.

## Verificação

```bash
mix test
mix compile --warnings-as-errors
```
