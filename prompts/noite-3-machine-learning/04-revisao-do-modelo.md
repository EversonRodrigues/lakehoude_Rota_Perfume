# Prompt 4 · Revisão do modelo — quando a fila mente sem errar uma conta

> **Antes de colar:** troque `<PERFIL>` e `<WAREHOUSE_ID>` pelos valores do seu
> ambiente — a tabela está em [prompts/README.md](../README.md#as-variáveis).

**Entrega:** duas correções em `gold.score_propensao` e `gold.fila_semanal`,
provadas com número antes e depois, mais um teste novo que impede a volta de
uma delas.

> Este prompt não nasceu de um plano de aula. Nasceu de duas perguntas feitas
> depois que tudo já estava no ar: *"por que um cliente com score 0,45 aparece
> como Muito quente?"* e *"por que a fila manda oferecer produto com estoque
> zerado?"*. As duas estavam certas, e nenhuma das duas era erro de conta — o
> job estava verde, os 9 testes passavam, a receita batia entre as camadas.
> **É esse o tipo de defeito que teste de pipeline não pega: o número está
> correto e mesmo assim comunica outra coisa.**

---

## Como auditar antes de mexer

A regra é uma só: **nenhuma correção antes do número que prova o defeito.** Sem
isso você troca um jeito de estar errado por outro e não tem como saber.

### 1. A faixa quer dizer o quê, exatamente?

```bash
databricks experimental aitools tools query --warehouse <WAREHOUSE_ID> --profile <PERFIL> \
  "SELECT faixa, COUNT(*) AS clientes, ROUND(MIN(score),4) AS score_min, ROUND(MAX(score),4) AS score_max
   FROM lakehouse_rotaperfume.gold.score_propensao GROUP BY faixa ORDER BY score_max"
```

O que voltou:

| faixa | clientes | score_min | score_max |
|---|---|---|---|
| Fria | 704 | 0,0000 | 0,0001 |
| Morna | 704 | 0,0001 | 0,0018 |
| Quente | 704 | 0,0018 | 0,0407 |
| **Muito quente** | **704** | **0,0407** | **0,9821** |

Quatro grupos de exatamente 704 é a assinatura de `NTILE(4)` — **quartil**. E
"Muito quente" ia de 0,04 a 0,98: **24 vezes de diferença sob a mesma palavra**.

### 2. E dentro da fila, que é onde alguém lê?

```bash
databricks experimental aitools tools query --warehouse <WAREHOUSE_ID> --profile <PERFIL> \
  "SELECT faixa, COUNT(*) AS linhas, ROUND(MIN(score),3) AS score_min, ROUND(MAX(score),3) AS score_max
   FROM lakehouse_rotaperfume.gold.fila_semanal GROUP BY faixa"
```

Uma linha só: `Muito quente | 200 | 0,270 | 0,982`.

**A coluna era constante exatamente onde é exibida.** E não podia ser diferente:
a fila são os 200 maiores scores, e o quartil de cima tem 704 clientes — os 200
cabem dentro dele por construção. O app e o Genie mostravam uma coluna com zero
informação, e ainda por cima uma que promete certeza.

### 3. O score pelo menos é confiável?

```bash
databricks experimental aitools tools query --warehouse <WAREHOUSE_ID> --profile <PERFIL> \
  "SELECT faixa, clientes, compraram, ROUND(score_medio,4) AS previsto,
          ROUND(taxa_de_compra,4) AS real
   FROM lakehouse_rotaperfume.gold.calibragem_holdout ORDER BY score_medio"
```

Com o quartil, a faixa de cima dava previsto **0,3009** e real **0,3011** — o que
parece calibragem perfeita. **Não era.** O quartil misturava 0,04 com 0,98 na
mesma média, e a média batia por acaso. Refeita a tabela com os cortes novos, o
mesmo holdout mostra outra coisa:

| faixa | clientes | previsto | real |
|---|---|---|---|
| Fria | 576 | 0,0099 | 0,0399 |
| Morna | 43 | 0,1429 | 0,2326 |
| Quente | 38 | 0,2900 | 0,3947 |
| **Muito quente** | **47** | **0,6942** | **0,4894** |

A taxa real **sobe faixa a faixa** — a ordenação presta, e é dela que vem o
`lift_top200` de 4,15×. Mas **na ponta de cima o modelo é otimista**: previa
0,69 e entregou 0,49. Agregado grosso esconde erro; foi só afinar o corte para
o erro aparecer.

### 4. Quantas linhas mandam oferecer o que não existe?

```bash
databricks experimental aitools tools query --warehouse <WAREHOUSE_ID> --profile <PERFIL> \
  "WITH ea AS (
     SELECT e.sku, e.saldo, e.ruptura FROM lakehouse_rotaperfume.silver.estoque e
     JOIN (SELECT sku, MAX(data_snapshot) AS d FROM lakehouse_rotaperfume.silver.estoque GROUP BY sku) u
       ON u.sku = e.sku AND u.d = e.data_snapshot)
   SELECT COUNT(*) AS linhas,
          COUNT_IF(f.sugestao LIKE 'Oferecer%' AND (ea.saldo <= 0 OR ea.ruptura)) AS oferecem_sem_estoque
   FROM lakehouse_rotaperfume.gold.fila_semanal f
   LEFT JOIN ea ON f.sugestao LIKE concat('Oferecer ', ea.sku, '%')"
```

**39 de 200** — uma em cada cinco ligações.

---

## O que estava errado no código

### A disponibilidade estava no lugar errado da consulta

```sql
-- ANTES: o estoque não participava da escolha
ROW_NUMBER() OVER (PARTITION BY fv.cliente_id ORDER BY SUM(fv.quantidade) DESC, fv.sku)
```

O saldo entrava por `LEFT JOIN` e só era olhado **depois**, no `CASE` que monta o
texto — que imprimia `Oferecer SKU00042 -- ATENCAO: saldo zerado`. O sistema
sabia que não tinha o produto e mandava oferecer assim mesmo, com uma ressalva
no fim da frase. **O vendedor lê o verbo, liga e promete.**

```sql
-- DEPOIS: disponibilidade primeiro, volume depois
ROW_NUMBER() OVER (
  PARTITION BY fv.cliente_id
  ORDER BY (COALESCE(ea.saldo, 0) > 0 AND NOT COALESCE(ea.ruptura, FALSE)) DESC,
           SUM(fv.quantidade) DESC, fv.sku)
```

**Por que no `ORDER BY` e não num `WHERE`:** filtrar deixaria o cliente sem
sugestão nenhuma. Ordenar mostra a segunda melhor opção *que existe no depósito*.
E a palavra "Oferecer" passou a aparecer só quando há saldo — sem saldo o texto
diz que não há o que oferecer, em vez de mandar oferecer com aviso.

### O quartil respondia a pergunta errada

Quartil responde *"em que posição ele está"*. Quem vai ligar precisa de *"qual é
a chance dele"*. Os cortes agora são múltiplos da **taxa base** medida no treino
(10,12% — a conversão de quem liga sem modelo): 1×, 2× e 4×.

```python
CORTES = {"Morna": 1.0, "Quente": 2.0, "Muito quente": 4.0}
```

Isso traz três propriedades que o quartil não tinha: a faixa significa a mesma
coisa toda semana, não muda de sentido porque a base de clientes cresceu, e
**volta a variar dentro da fila**. Junto veio a coluna `vezes_base` — porque
0,45 soa baixo até alguém ler que é **4,4× a média da base**. Número e
denominador andam juntos ou o número engana.

> A calibragem do holdout passou a usar **os mesmos cortes**. Uma tabela de
> calibragem com cortes diferentes dos que o usuário vê prova uma faixa que
> ninguém enxerga — foi exatamente o que escondeu o otimismo da ponta.

---

## Rodar e conferir

```bash
databricks bundle validate --strict --target dev --profile <PERFIL>
databricks bundle deploy --target dev --profile <PERFIL>

# o job_id sai do `bundle summary` do target — nunca copie de outro workspace
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["ml_modelo"]}'
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["ml_fila"]}'
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["auditoria_de_metadado"]}'
```

**Critério de aceite** — os três têm que passar:

| O que | Antes | Depois |
|---|---|---|
| linhas da fila mandando oferecer SKU sem saldo | **39** | **0** |
| faixas distintas dentro da fila | **1** (`Muito quente`, 200) | **2** (`Quente` 59, `Muito quente` 141) |
| `auditoria_de_metadado` com a coluna `vezes_base` nova | — | verde |

E o teste novo, que prende a correção do estoque, em `src/ml/11-fila.sql`:

```sql
SELECT 'teste 4 · nenhuma sugestao manda oferecer SKU sem saldo' AS teste, ...
       ELSE raise_error(...) END AS resultado
```

**Nunca relaxe esse teste para o job ficar verde.** Sugestão com estoque zerado
não é alarme falso — é promessa que o depósito não paga.

---

## Armadilhas

| Armadilha | Como aparece | O que fazer |
|---|---|---|
| **`NTILE` onde se esperava patamar** | quatro grupos de tamanho idêntico; o rótulo de cima cobre uma ordem de grandeza | corte absoluto ancorado numa referência do negócio (aqui, a taxa base) |
| **Coluna constante onde é exibida** | `GROUP BY` na tabela final devolve **uma linha** | teste o rótulo no recorte em que ele é lido, não na base inteira |
| **Calibragem agregada demais** | previsto bate com real "perfeitamente" | refine os cortes; média grossa cancela erro de sinais opostos |
| **Regra de negócio só no texto** | o `CASE` avisa, mas o `ORDER BY` já decidiu | a regra entra em **quem escolhe**, não em quem descreve |
| **Aviso no fim da frase** | `Oferecer X -- ATENCAO: ...` | mude o **verbo**; ressalva depois da ordem ninguém lê |
| **`--json` com argumento posicional** | `no positional arguments are allowed` | `job_id` vai **dentro** do JSON, não antes dele |
| **Acento e `█` no console do Windows** | `UnicodeEncodeError: 'charmap' codec` | escreva a consulta num arquivo UTF-8 e rode com `-f arquivo.sql` |

---

## O que ficou em aberto

O modelo **ordena melhor do que estima**. Isso não afeta o `lift_top200`, que só
depende da ordem, mas afeta todo número que multiplica o score por dinheiro: a
receita esperada da fila (`SUM(score * ticket_medio)`) herda o otimismo da ponta
de cima e é **estimativa por cima**. O conserto é calibrar o modelo
(`CalibratedClassifierCV`, isotônica, num pedaço separado do treino) e remedir a
tabela de calibragem. Fica para a próxima rodada — e está escrito nas instruções
dos dois Genie spaces, para que nenhuma resposta venda o score como promessa
enquanto isso não acontecer.
