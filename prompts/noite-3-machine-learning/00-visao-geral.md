# Os 3 prompts da Noite 3 — "Quais 200?"

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Imersão Jornada de Dados · Ciência de dados e agentes de IA · Quarta 26/08 · 19h30**

> **A noite inteira responde uma pergunta só:**
>
> *"Tenho 3.000 clientes. O time consegue ligar para 200 por semana.
> Quais 200?"*

Três prompts, três deploys. O `rotaperfume_pipeline` sai de **12 tarefas e
termina com 15**, e continua sendo um `bundle run` só.

```
prompt 1   + ml_features    gold.features_treino · gold.features_cliente
prompt 2   + ml_modelo      o modelo no UC · gold.score_propensao
prompt 3   + ml_fila        gold.fila_semanal · as 4 ferramentas
```

**Não existe "projeto de ML" separado.** ML é mais uma camada do mesmo
pipeline, no mesmo bundle, com os mesmos testes que quebram o job. É a tese da
noite, e o DAG é quem prova.

---

## Por que três, e não seis

A versão anterior desta noite tinha seis prompts: features, treino, score,
testes de modelo, decisão e retreino. Cada um bom, e o conjunto tirava o foco
da única coisa que o diretor perguntou.

**Um caso só, feito até o fim, ensina mais que seis pedaços.** Score, testes e
métricas não sumiram — foram para dentro dos três prompts, onde pertencem:

| Onde estava | Onde está agora |
|---|---|
| prompt 3 · score | dentro do prompt 2, logo depois do registro no UC |
| prompt 4 · 8 testes de modelo | 3 `assert` no prompt 2 e 3 `raise_error` no prompt 3 |
| prompt 5 · carteira do dia | virou a `fila_semanal` do prompt 3 |
| prompt 6 · challenger e rollback | vira menção de 90 segundos no fecho |

---

## Os três

| # | Entrega | Slides | Arquivo |
|---|---|---|---|
| 1 | **Features** — o que descreve um cliente | 16–22 | [`prompt-01-features.md`](prompt-01-features.md) |
| 2 | **Modelo e MLflow** — o baseline que choca | 23–37 | [`prompt-02-modelo.md`](prompt-02-modelo.md) |
| 3 | **A fila e o agente** — os 200, com motivo | 38–45 | [`prompt-03-fila-e-agente.md`](prompt-03-fila-e-agente.md) |

E, para ensaiar quantas vezes quiser:
[`99-limpar-aula-03.md`](99-limpar-aula-03.md) — apaga só a noite 3 e devolve
o ambiente ao fim da noite 2.

---

## Cronometragem

| Slides | Bloco | Min |
|---|---|---|
| 1–7 | A pergunta dos 200 | 14 |
| 8–9 | O plano da noite: três prompts, três deploys | 4 |
| 10–12 | A gold de ontem — a matéria-prima, com query na tela | 6 |
| 13–15 | **As premissas de ML** — o que é modelo, o vocabulário, o que assumimos | 7 |
| 16–22 | Feature engineering e as features · **prompt 1 rodando** | 19 |
| 23–30 | O modelo, o boosting, as alternativas, o AUC e o vazamento | 16 |
| 31–37 | **MLflow** — o que é, a anatomia de um run, por que aqui · **prompt 2 rodando** | 16 |
| 38–42 | A fila e o agente · **prompt 3 rodando** | 18 |
| 43–45 | Fecho | 5 |

**Total: ~105 min de conteúdo técnico.** Boa parte disso é fala enquanto o
Claude Code trabalha — os slides de conceito não são intervalo, são o que
preenche os três deploys.

### O deck curto (~85 min)

Se o relógio apertar, corte nesta ordem. Nenhum deles quebra o argumento:

| Slide | Por que sai primeiro |
|---|---|
| 10 e 11 | Fique só com o 12, que é o que amarra a limpeza na feature |
| 27 · Por que árvore e não Poisson | Vale mais como resposta quando a pergunta vem da sala |
| 35 · A anatomia de um run | Mostre a tela do MLflow no lugar — é mais convincente |
| 39 · Batch ou tempo real | Também é resposta de Q&A |
| 26 · Como a árvore aprende | Só se for necessário: é o slide que tira o mistério do `fit()` |

---

## Os números que têm que aparecer

A aula inteira converge para uma tabela só, e ela é a do slide *Não é acurácia*:

| Estratégia | AUC | Dos 200 abordados, quantos compram |
|---|---|---|
| Ligar aleatório | 0,5000 | **20** |
| Ligar para quem sumiu há mais tempo | **~0,37** | **0** |
| Ligar para os maiores | ~0,62 | 44 |
| **Ligar para os 200 de maior score** | **~0,85** | **75** — 3,7× |

Medidos no dataset com `seed 42`, corte `2026-08-01`, janela de **7 dias** e
score *out-of-fold* sobre os 2.809 clientes. A medição de referência usou 12
das 20 features, fora do Databricks: **os números da sua execução saem
impressos na tarefa `ml_modelo`, e são esses que vão para a tela.**

| Onde | Número |
|---|---|
| Clientes em `features_treino` | 2.809 |
| Taxa base da semana | **10,11%** |
| Feature nº 1 por permutação | `atraso_relativo` |
| Demonstração de vazamento | honesto ~0,867 → vazado **~0,9998** |

> **Por que a janela é de 7 dias e não de 30.** O rótulo precisa ter o mesmo
> horizonte da decisão. Com 30 dias, a taxa base sobe para 39,9% — ligar
> aleatoriamente já acerta 80 de 200, e o modelo chega a 179: um ganho real,
> mas de 2,2×, que não conversa com a pergunta semanal do diretor. Com 7 dias
> a pergunta e o rótulo são a mesma coisa.

---

## Como conduzir

| Regra | Por quê |
|---|---|
| Faça a pergunta dos 200 **antes** de abrir qualquer código | O resto da noite é a resposta dela |
| Segure o baseline até o prompt 2 | É o momento que a sala não espera. Não estrague |
| Abra o DAG depois de cada deploy | Continua sendo a melhor tela da aula |
| Quebre um teste de propósito no prompt 2 | Teste que ninguém viu falhar não convence ninguém |
| Fale em ligações, nunca em AUC, do slide 38 em diante | A partir dali quem escuta é o comercial |
| Não corrija tudo ao vivo | Um segundo prompt curto ensina mais que um conserto |

**Orçamento:** ~15 minutos por prompt, dos quais 9 a 11 são de fala sua.

---

## As armadilhas do Free Edition

Medidas contra o workspace. Estão dentro dos prompts, mas vale saber antes:

1. **`mlflow.pyfunc.spark_udf` não funciona no serverless.** Levanta
   `InvalidVersion: '18.x-aarch64-photon-scala2'`. É o caminho que toda
   documentação recomenda. A saída é `load_model` + pandas — e para 3.000
   clientes isso é a escolha certa de qualquer forma.

2. **XGBoost treina e registra, mas não carrega de volta.** Conflito com o
   scikit-learn 1.6.1 do serverless (`__sklearn_tags__`). Só se descobre uma
   tarefa depois. Use `HistGradientBoostingClassifier`.

3. **`mlflow.set_experiment` não cria a pasta pai.** O erro é
   `BAD_REQUEST: For input string: "None"`, que não menciona pasta nenhuma.
   `WorkspaceClient().workspace.mkdirs(...)` antes resolve.

4. **`DECIMAL` não serializa em JSON.** A gold usa `DECIMAL(18,2)`; toda
   feature numérica precisa de `.cast("double")`.

5. **`pyfunc.predict()` devolve a classe, não a probabilidade.** A coluna
   inteira vira zero e um, e a fila vira sorteio. Use `predict_proba()`.

6. **Não há endpoint de modelo próprio no Free Edition.** Por isso o consumo é
   batch, gravando `gold.score_propensao`. Para uma pergunta que muda uma vez
   por dia, é a arquitetura correta de qualquer forma.