# Limpar a noite 3 — para recriar tudo do zero

**Use antes de ensaiar, e de novo antes de subir ao vivo.** Se você não
consegue apagar, você não consegue provar que reconstrói.

Isto apaga **só a noite 3**. A noite 2 fica intacta: catálogo, bronze, silver,
gold, dashboard e Genie continuam de pé, e o job volta a ter 12 tarefas.

---

## O caminho rápido

```bash
bash aulas/aula-03-ciencia-de-dados/prompts/noite-3-machine-learning/99-limpar.sh <perfil>            # simula
bash aulas/aula-03-ciencia-de-dados/prompts/noite-3-machine-learning/99-limpar.sh <perfil> --apagar   # apaga
```

**Um comando e acabou.** Ele apaga no workspace, restaura o código local,
redeploya e **confere na tela** que não sobrou nada — saindo com erro se
sobrou. Rodar duas vezes seguidas dá o mesmo resultado.

---

## O que cada prompt deixa para trás

É isto que a limpeza precisa alcançar. Serve também para conferir à mão:

| Prompt | No workspace | No código |
|---|---|---|
| **1 · features** | `features_treino`, `features_cliente` | `src/ml/11-features.py`, tarefa `ml_features` |
| **2 · modelo** | `score_propensao`, `modelo_metricas`, `calibragem_holdout`, o modelo `propensao_compra` com versões e alias, o experimento MLflow | `src/ml/12-modelo.py`, tarefa `ml_modelo` |
| **3 · fila** | `fila_semanal`, as 4 funções | `src/ml/13-fila.sql`, tarefa `ml_fila`, **e o Genie Space** |

> **O Genie é o que mais se esquece.** O prompt 3 adiciona `fila_semanal` e
> `score_propensao` ao `comercial.geniespace.json`. Se as tabelas somem e o
> JSON continua citando elas, o próximo `bundle deploy` morre com
> `PERMISSION_DENIED ... Table ... does not exist` — e a mensagem não diz que o
> problema é o Genie.

---

## Como o script devolve o código ao lugar

Não editando YAML nem JSON: **restaurando do git**.

```bash
rm -rf src/ml
git restore --source=noite-2-pronta -- \
    resources/pipeline.job.yml resources/comercial.geniespace.json
```

`noite-2-pronta` é uma tag no commit em que a noite 3 ainda não existia. É
exata por construção, pega até o que ninguém previu, e continua funcionando se
você commitar o resultado dos prompts no meio da aula. Sem a tag, cai para
`HEAD`.

**A ordem não é negociável:** apagar no workspace → restaurar o código →
redeployar. Invertendo, o deploy roda com o JSON ainda citando tabela apagada.

Se o deploy pedir para apagar algo que não é da noite 3 — o dashboard, por
exemplo — o script **aborta e mostra a saída**. Nunca passe `--auto-approve`.

---

## O prompt

```
Apague tudo que a noite 3 criou no bundle
aulas/aula-02-engenharia-de-dados/rotaperfume/, e SÓ o que ela criou.
A noite 2 tem que continuar funcionando: não toque em bronze, silver, nas
tabelas gold que não são de ML, no dashboard nem no Genie Space.

Use o profile <perfil>.

1. No catálogo lakehouse_rotaperfume, na gold. Apague o que QUALQUER versão
   da noite 3 possa ter criado — o workspace pode estar na versão de três
   prompts ou na anterior, de seis:

     DROP TABLE    features_treino, features_cliente, score_propensao,
                   fila_semanal, modelo_metricas, calibragem_holdout,
                   modelo_importancia, modelo_promocoes, modelo_validacao
     DROP VIEW     carteira_do_dia, oportunidade_por_faixa, receita_em_risco
     DROP FUNCTION priorizar_carteira, contexto_cliente, sugerir_produtos,
                   checar_disponibilidade

   Todos com IF EXISTS — isto vai rodar de novo em cima do que já não existe.
   DROP TABLE não derruba view: as três precisam de DROP VIEW mesmo.

2. Apague o modelo registrado lakehouse_rotaperfume.gold.propensao_compra.
   O delete do modelo RECUSA enquanto houver versão viva — o erro é
   "Function ... is not empty. The function has N model versions(s)".
   Então apague as versões primeiro:
     databricks model-versions list <nome> --profile <perfil>
     databricks model-versions delete <nome> <versao> --profile <perfil>
     databricks registered-models delete <nome> --profile <perfil>

3. Apague o experimento do MLflow criado no treino, e a pasta que o continha.

4. Remova a pasta local src/ml/ inteira.

5. Em resources/pipeline.job.yml, remova TODAS as tarefas de ML — as da versão
   atual (ml_features, ml_modelo, ml_fila) e as da anterior (ml_treino,
   ml_promocao, ml_score, ml_testes, ml_carteira_do_dia) — e qualquer
   depends_on que aponte para elas. O job tem que voltar a terminar em
   auditoria_de_metadado, com 12 tarefas.

6. databricks bundle validate e depois deploy no target dev.
   Se o deploy pedir confirmação para APAGAR O DASHBOARD, pare e me avise:
   o dashboard é da noite 2 e não faz parte desta limpeza. Nunca use
   --auto-approve para passar por cima disso.

No fim, confirme na tela:
  - SHOW TABLES IN lakehouse_rotaperfume.gold  não lista nenhuma tabela de ML
  - databricks registered-models list --catalog-name lakehouse_rotaperfume
      --schema-name gold  devolve lista vazia
  - o job aparece com 12 tarefas
  - gold.fato_vendas continua respondendo
```

---

## O estado esperado depois — conferido no workspace

Depois de limpar e redeployar, é isto que tem que estar de pé. Se algum número
não bater, **não comece a noite 3**: o problema é da noite 2.

| O quê | Valor |
|---|---|
| `gold.fato_vendas` | 191.080 linhas · R$ 102.303.828,05 |
| Clientes com pedido antes de 2026-08-01 | 2.809 |
| Clientes com pedido antes de 2026-08-31 | 2.810 |
| `gold.dim_produto` | 292 SKUs |
| Views de negócio na gold | 6 (`receita_mensal`, `ranking_marcas`, `margem_por_categoria`, `clientes_em_risco`, `efeito_lancamento`, `ruptura_por_marca`) |
| Tarefas no `rotaperfume_pipeline` | 12 |
| Modelos registrados em `gold` | nenhum |
| Funções em `gold` | nenhuma |

> **As seis views são pré-requisito do Genie Space.** Se faltar qualquer uma,
> o `bundle deploy` falha com `PERMISSION_DENIED ... Table ... does not exist`
> — e a mensagem não deixa nada óbvio. Recrie com:
>
> ```bash
> python3 scripts/run_sql.py \
>   aulas/aula-02-engenharia-de-dados/rotaperfume/src/gold/09-metricas-negocio.sql \
>   --profile <perfil> --continuar
> ```

---

## Como conferir que sobrou só o que devia

```sql
-- não pode voltar nada
SHOW TABLES  IN lakehouse_rotaperfume.gold LIKE '*features*';
SHOW TABLES  IN lakehouse_rotaperfume.gold LIKE '*score*';
SHOW TABLES  IN lakehouse_rotaperfume.gold LIKE '*fila*';
SHOW TABLES  IN lakehouse_rotaperfume.gold LIKE '*modelo*';
SHOW VIEWS   IN lakehouse_rotaperfume.gold LIKE '*carteira*';

-- e a noite 2 tem que continuar em pé
SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.fato_vendas;
SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.dim_cliente;
```

`SHOW MODELS` não existe em SQL — modelo do Unity Catalog se lista pela CLI:

```bash
databricks registered-models list \
  --catalog-name lakehouse_rotaperfume --schema-name gold --profile <perfil>
```

---

## Se quiser apagar tudo, e não só a noite 3

Aí é o reset da noite 2, que derruba o catálogo inteiro e a pasta do bundle:

```bash
bash aulas/aula-02-engenharia-de-dados/prd/00-reset.sh <perfil> --apagar
```

Depois disso são **nove prompts** para reconstruir: os seis da noite 2 e os
três de hoje.