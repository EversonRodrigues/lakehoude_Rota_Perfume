# Prompt 4 · Revisão do modelo — quando a fila mente sem errar uma conta

> **Antes de colar:** troque `<PERFIL>` e `<WAREHOUSE_ID>` pelos valores do seu
> ambiente — a tabela está em [prompts/README.md](../README.md#as-variáveis).

**Entrega:** três correções em `gold.score_propensao` e `gold.fila_semanal` —
duas vindas de perguntas de quem usa, a terceira descoberta pela auditoria das
duas primeiras — provadas com número antes e depois, mais dois testes novos que
impedem a volta delas.

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

## Calibrar — e por que Brier, e não AUC

Sobrou a terceira correção: **o modelo ordenava melhor do que estimava.** Isso
não toca o `lift_top200`, que só olha a ordem, mas inflava tudo que multiplica
score por dinheiro — e a receita esperada da fila estava na tela do diretor.

**A escolha do método virou código, não opinião:**

```python
TOLERANCIA_AUC = 0.01

for metodo in ("cru", "sigmoid", "isotonic"):
    est = novo_estimador(metodo).fit(X_tr, y_tr)   # CalibratedClassifierCV(cv=5)
    ...

elegiveis = {k: v for k, v in candidatos.items() if v["auc"] >= auc_cru - TOLERANCIA_AUC}
calibragem_escolhida = min(elegiveis, key=lambda k: elegiveis[k]["brier"])
```

Três coisas para levar embora:

- **`CalibratedClassifierCV(cv=5)` calibra sem vazar.** Ele treina cinco modelos
  e ajusta a curva de cada um no fold que ele *não* viu. Calibrar no mesmo dado
  do fit devolve uma curva linda e mentirosa — e o holdout `X_te` continua
  intocado, para a medição final valer alguma coisa.
- **Brier, nunca AUC.** AUC é **invariante a qualquer transformação monótona**,
  e calibragem é exatamente isso: AUC não consegue enxergar a diferença. Brier é
  o erro quadrático da probabilidade — é a métrica que enxerga.
- **Calibragem não pode custar ordenação.** A fila é ordenação. Por isso o filtro
  de AUC vem antes do critério de Brier, e não o contrário.

Venceu **sigmoid** (Platt), não isotônica — com ~214 positivos no treino, a
isotônica tem dado demais para ajustar e ruído de sobra. Um quarto `assert`
derruba a tarefa se calibrar piorar o Brier, que é a assinatura da curva
sobreajustando o fold.

```bash
databricks bundle deploy --target dev --profile <PERFIL>
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["ml_modelo"]}'
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["ml_fila"]}'
databricks jobs run-now --profile <PERFIL> --json '{"job_id":<JOB_ID>,"only":["auditoria_de_metadado"]}'
```

### A calibragem remedida

| faixa | clientes | previsto | real | previsto/real |
|---|---|---|---|---|
| Fria | 459 | 0,0326 | 0,0196 | 1,66 |
| Morna | 124 | 0,1465 | 0,1210 | 1,21 |
| Quente | 95 | 0,2826 | 0,3579 | 0,79 |
| **Muito quente** | **26** | **0,4860** | **0,5000** | **0,97** |

A ponta de cima saiu de **1,42** para **0,97**. A taxa medida continua subindo
faixa a faixa (2,0% → 12,1% → 35,8% → 50,0%), então a ordenação não se perdeu.

### O placar

| | Antes | Depois |
|---|---|---|
| calibragem | nenhuma | **sigmoid** |
| Brier no holdout | 0,0775 | **0,0705** |
| AUC | 0,8816 | **0,8853** |
| `lift_top200` | 4,15× | **4,44×** |
| `acertos_top200` | 84 | **90** |
| faixa "Muito quente": previsto vs real | 0,6942 / 0,4894 | **0,4860 / 0,5000** |
| receita esperada da fila | R$ 556.423,71 | **R$ 388.987,57** |
| mix da fila | 59 Quente / 141 Muito quente | **139 / 61** |

**A receita esperada caiu 30%, e essa queda é o resultado.** Aquele pedaço era
otimismo do modelo, e estava na tela de quem decide. `lift_top200` subiu junto
porque o `cross_val_predict` passou a usar **o mesmo estimador que vai para
produção** — medir o lift de um modelo e publicar outro é testar o freio de
outro carro.

Continua sendo **estimativa**, e o Genie continua obrigado a dizer a palavra:
soma de probabilidade vezes ticket histórico não é pedido faturado.

---

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
| faixas distintas dentro da fila | **1** (`Muito quente`, 200) | **2** (`Quente` 139, `Muito quente` 61) |
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
| **Medir calibragem com AUC** | AUC não muda depois de calibrar | AUC é invariante a transformação monótona; use **Brier** |
| **Calibrar no dado do fit** | curva perfeita que não se sustenta | `CalibratedClassifierCV(cv=5)` ajusta no fold que o modelo não viu |
| **Isotônica com poucos positivos** | Brier piora em vez de melhorar | compare com sigmoid e deixe a medida escolher |
| **Medir o lift de um modelo e publicar outro** | o número não bate depois | `cross_val_predict` no **mesmo** estimador que vai para produção |
| **`--json` com argumento posicional** | `no positional arguments are allowed` | `job_id` vai **dentro** do JSON, não antes dele |
| **Acento e `█` no console do Windows** | `UnicodeEncodeError: 'charmap' codec` | escreva a consulta num arquivo UTF-8 e rode com `-f arquivo.sql` |

---

## O que ficou em aberto

A faixa **Fria** ainda estima 1,66× acima do medido (0,0326 contra 0,0196). Em
valor absoluto é 1,3 ponto percentual e não muda decisão nenhuma — ninguém liga
para a faixa fria —, mas é o lembrete de que calibragem é local: ela acertou
onde foi medida e cobrada, a ponta de cima.

A amostra da faixa de cima no holdout é **26 clientes**. É pouco para cravar
0,486 contra 0,500 como se fosse precisão de três casas; o que a medida sustenta
é que o viés sistemático de 1,42× sumiu, não que o número esteja exato.
