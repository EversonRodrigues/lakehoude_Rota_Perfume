# Os 3 prompts da Noite 4 — "E quem não escreve SQL?"

**Imersão Jornada de Dados · Apps e agentes · Quinta 27/08 · 19h30**

> **A noite inteira responde uma pergunta só:**
>
> *"O pipeline roda, o modelo escolhe os 200. Como o diretor vê isso —
> e como o vendedor devolve o que aconteceu?"*

Três prompts, três deploys. O bundle da terça ganha uma tabela e duas tarefas
(13 → **15 tarefas**), e nasce um segundo artefato ao lado dele: **um Databricks
App**, com deploy próprio.

```
prompt 1   + genie_direcao      o Genie da direção · gold.retorno_ligacao
prompt 2   + app                a fila dos 200 na tela, com o Genie dentro
prompt 3   + POST /api/retorno  o resultado da ligação volta para a gold
```

**Nada de dado novo.** Toda a noite consome o que as três anteriores
construíram: `gold.fila_semanal`, `gold.score_propensao`,
`gold.modelo_metricas`. A única tabela que nasce hoje é a que recebe a resposta
do time — e ela nasce vazia de propósito.

---

## Por que esta noite existe

As três primeiras noites terminaram com o dado certo no lugar certo. E com um
problema que nenhuma delas resolveu: **tudo que a gente construiu só é acessível
por quem sabe abrir um SQL Editor.**

| Noite | O que ficou de pé | O que era preciso saber |
|---|---|---|
| 1 | O dado no catálogo | SQL |
| 2 | O pipeline, o dashboard e o Genie | Python e PySpark |
| 3 | O modelo e a fila dos 200 | ML e SQL |
| **4** | **O app e o Genie da direção** | **nada** |

O último metro da noite 3 foi traduzir score em motivo. O último metro **desta**
noite é entregar uma URL.

> **A frase da noite:** um dado que só o time de dados consegue abrir é um dado
> que não existe para a empresa.

---

## Os três

| # | Entrega | Deploy | Arquivo |
|---|---|---|---|
| 1 | **O Genie da direção** — o produto que se pergunta | `bundle deploy` | [`prompt-01-genie.md`](prompt-01-genie.md) |
| 2 | **O app** — a fila dos 200 na tela | `apps deploy` | [`prompt-02-app.md`](prompt-02-app.md) |
| 3 | **O retorno** — o ciclo se fecha | `apps deploy` | [`prompt-03-retorno.md`](prompt-03-retorno.md) |

E, para ensaiar quantas vezes quiser:
[`99-limpar-aula-04.md`](99-limpar-aula-04.md) — apaga só a noite 4 e devolve o
ambiente ao fim da noite 3.

---

## Cronometragem

| Slides | Bloco | Min |
|---|---|---|
| 1–6 | A pergunta: e quem não escreve SQL? | 12 |
| 7–14 | **A recapitulação em visão de negócio** — as três noites, etapa por etapa | 16 |
| 15–18 | As três portas: dashboard, Genie, app — e quando usar cada uma | 8 |
| 19–24 | O Genie como produto · **prompt 1 rodando** | 15 |
| 25–33 | Databricks Apps · **prompt 2 rodando** | 22 |
| 34–41 | O retorno da ligação · o teste do ciclo · **prompt 3 rodando** | 18 |
| 42–47 | O ciclo completo, a documentação, portfólio e fecho | 12 |

**Total: ~103 min**, em 47 slides.

O bloco 7–14 é o mais importante da noite para quem chegou hoje — e é o único
lugar do curso onde as três noites são contadas **na língua do negócio**, sem
uma palavra de arquitetura.

---

## Os números que têm que aparecer

Todos medidos no workspace `rotaperfumes` (profile `rotaperfumes`, catálogo
`lakehouse_rotaperfume`), depois de uma execução completa do pipeline:

| Onde | Número |
|---|---|
| Tarefas no job | **13** no começo da noite, **15** no fim |
| Contatos na fila | **200**, em **36** vendedores |
| Receita esperada da fila | **R$ 556.423,71** (soma de `score × ticket_medio`) |
| Conversão prevista | **42%** — 84 dos 200 — contra **10,1%** ligando às cegas |
| Ganho do modelo | **4,15×** (`lift_top200`) |
| Maior score da semana | **0,982** — Perfumaria Prime Ltda, Curitiba |
| Retornos registrados no começo da noite | **0** — e é assim que tem que ser |
| Colunas da gold sem COMMENT | **65** antes do prompt 1, **0** depois |
| Receita que sobrevive a toda camada | **R$ 102.303.828,05** |

> **Estes números são deste repositório, não do roteiro original do curso.** O
> material de aula foi escrito contra outro workspace e traz 582.799,50, 4,25×,
> 86/200 e 35 vendedores. Se a sala perguntar, a resposta honesta é boa: o
> pipeline é o mesmo, os dados de origem são os mesmos, e o modelo é
> determinístico — o que muda é o ambiente. Rode e leia o seu.

| Tempo medido | Quanto |
|---|---|
| `databricks apps init` (scaffold + npm install) | **~60s** |
| **Primeiro** `apps deploy` (cria o compute) | **3m44s** |
| Redeploy | **1m04s** |
| `bundle deploy` do Genie | **~20s** |

> **Planeje a fala em cima desses tempos.** O primeiro deploy do app é o mais
> longo da imersão inteira — são quase quatro minutos de tela parada. É onde
> entra o bloco de recapitulação, não um silêncio constrangido.

---

## Como conduzir

| Regra | Por quê |
|---|---|
| Abra a noite com a URL do app **fechada** | A sala precisa sentir a falta antes de ver a solução |
| Faça a recapitulação **antes** do primeiro prompt | Metade da audiência da última noite é nova |
| Rode o primeiro `apps deploy` e **fale por cima** | São 3m44s. Tenha os slides 25–30 prontos para preencher |
| Peça uma pergunta da sala para o Genie | Ele erra às vezes, e é ótimo: mostre o SQL gerado |
| Clique em "Vendeu" ao vivo e **volte para o SQL** | Ver a linha aparecer em `gold.retorno_ligacao` é o momento da noite |
| Não conserte CSS ao vivo | A noite é sobre acesso ao dado, não sobre front-end |

**Orçamento:** ~15 minutos por prompt, dos quais 9 a 11 são de fala sua.

---

## As armadilhas medidas

1. **O app é um usuário do Unity Catalog, e começa sem permissão nenhuma.**
   `permission: CAN_USE` no warehouse **não** dá acesso aos dados. Sem os três
   `GRANT` para o service principal, toda tela carrega vazia com erro de
   permissão. É o erro nº 1 de apps, e está no prompt 2.

2. **O service principal muda a cada app criado.** Não copie o id de outro
   ambiente: leia com `databricks apps get`.

3. **`useAnalyticsQuery` não tem `refetch`.** Depois de gravar o retorno, a
   tela não se atualiza sozinha. A saída é um parâmetro de recarga que muda a
   chave do cache — está no prompt 3.

4. **O typegen precisa do warehouse ligado.** Com o warehouse parado ele
   degrada para `OFFLINE` e gera `{}` como tipo — e o `tsc` quebra com erros
   que não têm nada a ver com o problema real. Ligue o warehouse antes.

5. **`databricks bundle deploy` não sobe o app.** Ele cria o app com
   `no_compute` e o deixa parado, sem URL. Para app, o comando é
   `databricks apps deploy`.

6. **O target do app se chama `default`, não `dev`.** O bundle do app é gerado
   pelo `apps init` e não segue os targets do bundle da noite 2.
