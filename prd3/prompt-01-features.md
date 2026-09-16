# Prompt 1 · Features — o que descreve um cliente

**Slides que acompanham:** 16 a 22 (divisor *"O que descreve um cliente"*, **o
que é feature engineering**, de *"O que descreve um cliente"*, de
onde vêm as features, RFM, os dois clientes com a mesma recência, atraso
relativo, os quatro grupos).

**Entrega:** `gold.features_cliente` e `gold.features_treino`, geradas pela
mesma função com datas diferentes. **Deploy nº 1 da noite.**

> A tentação é começar pelo modelo. Comece pelas features: o modelo é o mesmo
> `.fit()` para todo mundo, e é aqui que sai a diferença entre o projeto que
> funciona e o que impressiona no notebook e morre em produção.

---

## O ambiente, conferido hoje

Rodado contra `lakehouse_rotaperfume` no workspace. **Tudo o que este prompt
usa já existe** — nenhuma fonte precisa ser criada antes:

| Tabela | O que este prompt lê dela |
|---|---|
| `gold.fato_vendas` | 191.080 linhas · R$ 102.303.828,05 · já traz `categoria`, `marca`, `canal` e `devolucao` |
| `gold.dim_produto` | 292 SKUs, com `data_lancamento` |
| `silver.oportunidades` | `data_abertura`, `etapa`, `ganha` |
| `silver.visitas` | `data_visita`, `gerou_pedido` |

O job está com **10 tarefas** e o `bundle deploy` passa limpo — vira **11** com a
`ml_features` desta noite.

> **Este repositório difere do ambiente descrito no material original** em três
> pontos que mudam o prompt: a tarefa final de qualidade chama-se **`testes`**
> (não `testes_de_qualidade`), a chave do dashboard é **`comercial`** (não
> `dashboard_comercial`), e **não existe a auditoria de metadado da noite 2** —
> escreva os `COMMENT` mesmo assim, mas saiba que aqui nada os cobra, e a linha
> correspondente da tabela "Se der errado" não pode acontecer.

> **No deploy, se aparecer pedido de confirmação para APAGAR O DASHBOARD:
> recuse e me chame.** O dashboard é da noite 2 e a chave do recurso
> (`dashboard_comercial`) não pode ser renomeada — trocar a chave faz o bundle
> apagar e recriar, com URL nova. **Nunca use `--auto-approve` aqui.**

---

## O que mostrar antes

**1 · A gold sabe tudo sobre ontem e nada sobre a semana que vem**

```sql
-- tudo que já aconteceu
SELECT COUNT(*) AS linhas, ROUND(SUM(receita), 2) AS receita
FROM lakehouse_rotaperfume.gold.fato_vendas;

-- e a pergunta que ela NÃO responde: quais destes 3.000 eu ligo?
SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.dim_cliente;
```

> *"Duas noites de trabalho responderam tudo sobre o passado. O diretor não
> perguntou nada sobre o passado. Ele perguntou quais 200."*

**2 · O formato que o modelo precisa, e que a gold não tem**

```sql
-- o fato tem uma linha por ITEM. O modelo precisa de uma linha por CLIENTE.
SELECT cliente_id, COUNT(*) AS linhas_no_fato
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY cliente_id ORDER BY 2 DESC LIMIT 5;
```

**3 · Os dois clientes do slide *Dois clientes, a mesma recência*, no dado real**

Rode antes de colar o prompt. É o argumento inteiro da noite em uma query:

```sql
WITH ritmo AS (
  SELECT cliente_id,
         DATEDIFF('2026-08-31', MAX(data_pedido))                     AS recencia,
         DATEDIFF(MAX(data_pedido), MIN(data_pedido))
           / NULLIF(COUNT(DISTINCT pedido_id) - 1, 0)                 AS intervalo
  FROM lakehouse_rotaperfume.gold.fato_vendas
  GROUP BY cliente_id HAVING COUNT(DISTINCT pedido_id) >= 5)
SELECT cliente_id, recencia, ROUND(intervalo, 1) AS intervalo_medio,
       ROUND(recencia / intervalo, 1)            AS atraso_relativo
FROM ritmo
WHERE recencia BETWEEN 18 AND 22    -- a MESMA recência
ORDER BY atraso_relativo DESC LIMIT 6;
```

Dois clientes com a mesma recência e atrasos relativos opostos aparecem na
mesma tela. **Pare aqui e deixe a sala olhar.** Ordenar por recência colocaria
os dois na mesma posição da fila.

---

**Enquanto ele trabalha, você explica:**

- **Feature é conhecimento de negócio virando coluna.** `recencia_dias` está em
  qualquer tutorial. `atraso_relativo` não está em nenhum, porque depende de
  saber que distribuição funciona por ciclo de reposição.
- **A janela é de sete dias porque a fila é semanal.** O rótulo tem que ter o
  mesmo horizonte da decisão: o time liga para 200 por semana, então a pergunta
  é "compra nesta semana", não "compra em algum momento do mês".
- **A data de corte é a espinha do arquivo.** Toda feature é calculada com dado
  anterior a uma data que entra por parâmetro. Não é disciplina pessoal, é
  assinatura de função.
- **Uma função, dois usos.** A mesma `montar_features()` gera o dado de treino
  (com rótulo) e o de score (sem rótulo). É impossível os dois divergirem — e
  esse desencontro tem nome, *training/serving skew*, e é o que o Feature Store
  resolve com infraestrutura. Aqui está resolvido com um `def`.
- **Tabela de feature é gold.** Comentada, testada e auditada como qualquer
  outra: a auditoria de metadado de ontem quebra o job se faltar `COMMENT`.

---

## O prompt

```
Continue o bundle em aulas/aula-02-engenharia-de-dados/rotaperfume/.
A gold está pronta, testada e com metadado auditado. Começa a camada de ML.

Crie src/ml/11-features.py — um notebook Python para serverless.

Defina UMA função montar_features(referencia) que devolve uma linha por
cliente com tudo que se sabia dele ATÉ essa data. Cada fonte é filtrada pela
data dela na primeira linha da leitura, sem exceção:

  gold.fato_vendas        data_pedido   < referencia
  silver.oportunidades    data_abertura < referencia
  silver.visitas          data_visita   < referencia

NÃO use gold.dim_cliente para feature nenhuma. Ela tem dias_sem_comprar,
receita_acumulada e total_pedidos calculados sobre a base INTEIRA, sem corte —
usar qualquer uma delas é vazamento, e é o erro que o notebook 02 demonstra.
dim_cliente só entra no prompt 3, para pegar nome e cidade.

Vinte features, em quatro grupos. Tudo sai de gold.fato_vendas, que já traz
razao_social, canal, categoria e marca — não precisa de join para isso:

  RFM
    recencia_dias        = datediff(referencia, max(data_pedido))
    frequencia_pedidos   = count(distinct pedido_id)
    valor_total          = sum(receita)   -- devolução já entra negativa
    ticket_medio         = valor_total / frequencia_pedidos
    margem_total         = sum(margem)
    margem_percentual    = margem_total / nullif(valor_total, 0)

  Ritmo
    intervalo_medio_dias   = datediff(max, min) / (pedidos distintos - 1)
    desvio_intervalo_dias  = desvio padrão dos intervalos entre pedidos
    atraso_relativo        = recencia_dias / intervalo_medio_dias,
                             com NULLIF no denominador e teto em 10
    pedidos_ultimos_90d    = pedidos distintos nos 90 dias antes do corte

  CRM
    oportunidades_abertas  = etapa não fechada, de silver.oportunidades
    oportunidades_ganhas   = coluna ganha
    taxa_ganho             = ganhas / nullif(total de oportunidades, 0)
    visitas_90d            = visitas nos 90 dias antes do corte
    conversao_visita       = visitas com gerou_pedido / nullif(visitas, 0)

  Mix
    skus_distintos          = count(distinct sku)
    categorias_distintas    = count(distinct categoria)
    concentracao_marca_top  = receita da marca top / nullif(valor_total, 0)
    comprou_lancamento      = 1 se comprou algum SKU cuja data_lancamento
                              (de gold.dim_produto) esteja nos 120 dias
                              anteriores ao corte. É o único join necessário.

Grave duas tabelas, chamando a MESMA função duas vezes:

  gold.features_treino   referencia = 2026-08-01, mais a coluna alvo
                         comprou_em_7d = 1 se o cliente fez pedido entre
                         2026-08-01 e 2026-08-07 — a janela é de UMA SEMANA,
                         porque a fila que o time vai atacar é semanal
  gold.features_cliente  referencia = 2026-08-31, sem alvo — é o que vai
                         ser pontuado

As duas gravam uma coluna _referencia com a data de corte usada. Toda soma de
receita ou margem sai da gold como DECIMAL(18,2): use cast para double em
TODAS as features numéricas, senão o registro do modelo quebra depois com
"Object of type Decimal is not JSON serializable".

Cliente sem oportunidade ou sem visita fica com 0, não com NULL — só as
features de ritmo podem ser NULL, para cliente com um pedido só.

Nada de current_date() em lugar nenhum: o "hoje" deste dataset é 2026-08-31.

Toda tabela e toda coluna com COMMENT em português — a auditoria de metadado
da noite 2 quebra o job se faltar.

Depois registre a tarefa ml_features em resources/pipeline.job.yml, rodando
depois de testes_de_qualidade — modelo não se treina com dado que ainda não
passou nos testes — e faça o deploy.
```

---

## Como verificar a feature

**1 · As duas tabelas nasceram do mesmo corte declarado**

```sql
SELECT '_treino' AS tabela, COUNT(*) AS clientes, MIN(_referencia) AS corte
FROM lakehouse_rotaperfume.gold.features_treino
UNION ALL
SELECT '_cliente', COUNT(*), MIN(_referencia)
FROM lakehouse_rotaperfume.gold.features_cliente;
```

**2.815 e 2.816 clientes** — medido neste workspace — com `2026-08-01` e
`2026-08-31` declarados na própria linha. **A data de corte não é comentário no
código: é coluna na tabela.**

> A medição de referência deste material dizia 2.809/2.810. Ela foi feita fora do
> Databricks, com 12 das 20 features; a diferença de 6 clientes não aparece em
> nenhuma variação de coorte que eu tenha testado (`<` contra `<=`, excluir
> devolução, filtrar cliente ativo). **Use sempre o número que sair da sua
> execução** — é o que vai para o quadro.

**2 · A taxa base — o número que vai virar régua no prompt 2**

```sql
SELECT COUNT(*)                                   AS clientes,
       SUM(comprou_em_7d)                         AS compraram,
       ROUND(100 * AVG(comprou_em_7d), 2)         AS taxa_base_pct
FROM lakehouse_rotaperfume.gold.features_treino;
```

**Aqui deu 2.815 clientes, 285 compradores e taxa base de 10,12%** — rodado
neste workspace. Ou seja, **20 de cada 200 ligações às cegas viram pedido.**

> **Anote os dois números no quadro.** É o "20" do slide *Não é acurácia*, e todo o prompt 2 é
> a tentativa de superá-lo.

**3 · A feature que ordena a fila**

```sql
SELECT c.razao_social,
       f.recencia_dias,
       ROUND(f.intervalo_medio_dias, 1) AS intervalo_medio,
       ROUND(f.atraso_relativo, 1)      AS atraso
FROM lakehouse_rotaperfume.gold.features_cliente f
JOIN lakehouse_rotaperfume.gold.dim_cliente c USING (cliente_id)
ORDER BY f.atraso_relativo DESC LIMIT 10;
```

**4 · A prova de que não há vazamento**

```sql
-- nenhum cliente pode ter comprado DEPOIS do corte e isso aparecer na recência
SELECT MIN(recencia_dias) AS menor_recencia
FROM lakehouse_rotaperfume.gold.features_treino;
```

Se `menor_recencia` vier negativa, uma fonte escapou do filtro. **Recência
negativa é a assinatura do vazamento** — é o que o notebook
`02-o-vazamento-de-dado.py` demonstra de propósito.

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| `Object of type Decimal is not JSON serializable` | soma de receita veio `DECIMAL(18,2)` | `.cast("double")` em todas as features numéricas |
| `atraso_relativo` com valores absurdos (10.000) | cliente com um pedido só: intervalo 0 | `NULLIF` no denominador e teto em 10 |
| `atraso_relativo` = 10 em cliente de **um pedido só** | o teto foi feito com `F.least(razao, 10)`, e o `least` do Spark **ignora nulo**: `least(NULL, 10)` devolve **10** | Use `when(razao > 10, 10).otherwise(razao)`, que propaga o nulo. **Medido aqui:** os 105 clientes de pedido único iam para o topo da fila com alarme máximo, sem que se soubesse nada do ritmo deles |
| A auditoria de metadado quebrou o job | faltou `COMMENT` em coluna nova | é o teste da noite 2 funcionando — peça o comentário e rode de novo |
| Alguma feature veio de `dim_cliente` | ela agrega a base inteira, sem corte | é vazamento: peça para refazer a partir do fato. **Mostre ao vivo** — é o slide do vazamento acontecendo |
| `menor_recencia` negativa | filtro `< referencia` faltou em uma fonte | mostre ao vivo: é o slide *Prever a semana que vem com informação da semana que vem* acontecendo |