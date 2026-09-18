# Prompt 5 · Dashboard como código

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Entrega:** o AI/BI dashboard comercial versionado no bundle, subindo junto com
o deploy. **Deploy nº 5.**

> Conceito que quase ninguém ensina. Ontem eles viram dashboard **clicado**.
> Hoje veem dashboard **em JSON, no repositório, dentro do bundle**.

---

## O que mostrar antes

Abra o dashboard da noite 1 lado a lado com o editor. São duas comparações, e a
segunda é a que fica.

**1 · O SQL que o dashboard de ontem precisava — porque lia a bronze**

```sql
-- receita por mês, na noite 1
SELECT date_trunc('month', coalesce(try_to_date(data_pedido),
                                    try_to_date(data_pedido, 'dd/MM/yyyy'))) AS mes,
       ROUND(SUM(try_cast(valor_total AS DECIMAL(18,2))), 2) AS receita
FROM lakehouse_rotaperfume.bronze.pedidos
WHERE status <> 'Cancelado'
GROUP BY 1 ORDER BY 1;
```

**2 · O mesmo gráfico, hoje, lendo a gold**

```sql
SELECT ano, mes, ROUND(SUM(receita), 2) AS receita
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY ano, mes ORDER BY ano, mes;
```

Os dois dão o mesmo total. Um tem dois `try_to_date`, um `try_cast` e uma regra
de negócio solta no `WHERE`; o outro tem `SUM(receita)`. **Isso é o que a silver
e a gold compraram** — e é o argumento que convence quem já trabalha com dados.

**3 · E a pergunta que expõe o problema do dashboard clicado**

```bash
ls aulas/aula-02-engenharia-de-dados/rotaperfume/resources/*.lvdash.json
# não existe: o dashboard de ontem mora só no workspace
git log --oneline -- '*dashboard*'      # nada para mostrar
```

> *"Quem aqui consegue me dizer o que mudou no dashboard da sua empresa na
> semana passada, e quem mudou? Dashboard clicado não tem diff, não tem revisão
> e não tem rollback."*

---

**Enquanto ele trabalha, você explica:**

- **Dashboard clicado não tem diff, não tem revisão, não tem rollback.** Se
  alguém apaga um widget na sexta, ninguém sabe o que tinha lá. Em JSON versionado,
  é `git revert`.
- **Métrica declarada uma vez.** Com `MEASURE()` no dataset, receita é definida
  num lugar só. Nenhuma tela mostra número diferente da outra — que é o motivo
  número um de reunião travada.
- **Compare o SQL com o de ontem.** O dashboard da noite 1 lia a bronze: cada
  dataset carregava `CAST` e dois `try_to_date`. O de hoje lê a gold: `receita`,
  `data_pedido`, `margem`. Metade do SQL. É isso que a silver comprou.
- **Sobre a margem por categoria:** é a descoberta que faz diretor comercial
  prestar atenção. Kit Presente vende muito e ganha pouco — 33,0% contra 49,9%
  do Óleo Concentrado. O gráfico ordenado crescente deixa isso óbvio em dois
  segundos.

---

## O prompt

```
Continue o bundle em aulas/aula-02-engenharia-de-dados/rotaperfume/.
A gold está de pé e os 9 testes passam. Agora o dashboard, como código.

Crie resources/dashboard-comercial.lvdash.json e declare-o em
resources/dashboard.dashboard.yml como recurso do tipo `dashboards`, com
file_path, warehouse_id, dataset_catalog e dataset_schema (gold), para que
suba junto no deploy.

REGRAS QUE QUEBRAM O DASHBOARD SE FOREM IGNORADAS:
- As queries do JSON usam nome de tabela PURO: `FROM fato_vendas`. Nunca
  `FROM gold.fato_vendas`. O catálogo e o schema vêm do dataset_catalog e
  dataset_schema — se você prefixar, eles são ignorados.
- Use POUCOS datasets. Widgets que compartilham dataset filtram juntos: clicar
  numa marca filtra a tela inteira. Datasets separados quebram isso. Um dataset
  largo sobre fato_vendas atende KPIs, linha, barras e filtros.
- O `name` em `query.fields` tem que bater EXATAMENTE com o `fieldName` em
  `encodings`, senão o widget mostra "no selected fields to visualize".
- Versão do widget: counter e table são version 2; bar e line são version 3;
  filtros são version 2. Versão errada = widget quebrado.
- Toda página precisa de `"layoutVersion": "GRID_V1"`.

Nada de CAST, nada de try_to_date no SQL dos datasets — se você precisar de um,
a gold está errada e o problema é lá.

VISÕES
- Quatro cartões de KPI: receita total, margem total, número de pedidos,
  ticket médio. Declare as métricas UMA vez, em `columns` no dataset, e use
  MEASURE(`Receita`) nos widgets. É o que garante que nenhuma tela mostre
  receita diferente da outra.
- Linha: receita por mês, os 24 meses.
- Barras: top 10 marcas por receita.
- Barras: margem percentual por categoria, ORDENADA CRESCENTE — é o gráfico
  que mostra que Kit Presente vende muito e ganha pouco.
- Tabela: top 20 clientes por receita, com segmento e cidade.
- Barras: receita por canal.
- Filtros por ano, segmento e cidade, compartilhados entre os widgets, de
  forma que clicar numa marca filtre a tela inteira.

Teste TODAS as queries no warehouse antes de montar o JSON — nenhum widget
pode subir quebrado. Use o tema escuro/claro com `uiSettings.theme` e uma
paleta coerente; o padrão do workspace deixa o dashboard com cara de genérico.

Rode e me mostre a saída:
  databricks bundle validate --profile <PERFIL>
  databricks bundle deploy --target dev --profile <PERFIL>

Depois me dê o link do dashboard publicado.
```

---

## Como verificar a feature

**1 · Os números do dashboard batem com o número canônico da noite**

Antes de olhar para a tela, rode no warehouse a query que está por trás dos
quatro cartões de KPI:

```sql
SELECT ROUND(SUM(receita), 2)                        AS receita_total,
       ROUND(SUM(margem), 2)                         AS margem_total,
       COUNT(DISTINCT pedido_id)                     AS pedidos,
       ROUND(SUM(receita) / COUNT(DISTINCT pedido_id), 2) AS ticket_medio
FROM lakehouse_rotaperfume.gold.fato_vendas;
-- receita_total = R$ 102.303.828,05 — tem que ser IGUAL ao cartão do dashboard
```

**Se o cartão mostrar outro número, o widget está errado** — quase sempre um
filtro esquecido ou um dataset com `WHERE` a mais. É esse o motivo de testar
toda query antes de montar o JSON.

E a query do gráfico que faz o diretor comercial parar:

```sql
SELECT categoria,
       ROUND(SUM(receita)/1e6, 1)                 AS receita_mi,
       ROUND(100 * SUM(margem) / SUM(receita), 1) AS margem_pct
FROM lakehouse_rotaperfume.gold.fato_vendas
GROUP BY categoria ORDER BY margem_pct;     -- Kit Presente 33,0 na ponta esquerda
```

**2 · O dashboard subiu, e o bundle sabe onde ele está**

```bash
databricks bundle summary --target dev --profile <PERFIL>
# a saída traz a URL do dashboard publicado — abra a partir dela
```

**3 · É um arquivo no Git — a demonstração que vale a seção inteira**

> **Pré-requisito, e ele morde:** o `.lvdash.json` precisa estar **commitado**.
> Num repositório recém-criado, sem nenhum commit, `git diff` e `git checkout --`
> não têm contra o que comparar e a demonstração não roda. Faça
> `git add` + `git commit` do bundle **antes da aula**.
>
> Sem git, o round-trip ainda se prova com o arquivo: edite o título, `deploy`,
> mostre a mudança no dashboard; desfaça a edição, `deploy`, mostre que voltou.
> É o mesmo argumento — o dashboard é o arquivo — só sem o diff na tela.

```bash
# mude o título de um widget no JSON e mostre o diff
git diff -- '*lvdash.json'
databricks bundle deploy --target dev --profile <PERFIL>
# recarregue o dashboard: o título mudou

git checkout -- '*lvdash.json'
databricks bundle deploy --target dev --profile <PERFIL>
# e voltou. Isso é rollback de dashboard, em dois comandos.
```

**4 · Apague o dashboard ao vivo e traga de volta**

Delete o dashboard pela interface, na frente da turma. Depois:

```bash
databricks bundle deploy --target dev --profile <PERFIL>
```

Ele volta idêntico, com os mesmos widgets e as mesmas cores.

> **Diga isso, porque a turma vai reparar:** o dashboard volta com **URL nova**.
> O conteúdo é idêntico — os 14 widgets, o tema, as métricas — mas o id muda, e
> quem tinha o link antigo fica com um link morto. Medido: o id saiu de
> `…9f6d1396…` para `…c70e1f73…`. Recuperar o dashboard é automático; **redistribuir
> o link, não.** Por isso o link do dashboard vai no `bundle summary`, não num
> e-mail de 2023.

> *"Dashboard clicado, quando alguém apaga, acabou — e normalmente a pessoa que
> sabia montar já saiu da empresa."*

**5 · O filtro cruzado funciona — a prova de que os widgets dividem o dataset**

Clique numa marca no gráfico de barras: **a tela inteira filtra**, KPIs
incluídos. Se um widget não acompanhar, ele tem dataset próprio — é o erro que
está na tabela de sintomas no fim deste prompt.

---

## Fala de aula

> *"Esse dashboard responde exatamente as mesmas perguntas do que vocês viram
> ontem. Mas abre o SQL de um dataset comigo: ontem era `CAST(valor_total AS
> DECIMAL)` mais dois `try_to_date` em toda query. Hoje é `receita`. Metade do
> código, e ninguém mais precisa lembrar de qual coluna converter.*
>
> *E o principal: se eu apagar esse dashboard agora, um `deploy` traz ele de
> volta idêntico. Dashboard clicado, se alguém apagar, acabou — e normalmente
> a pessoa que sabia montar já saiu da empresa."*

> **Contingência:** se o tempo estourar, este é o prompt para cortar. Dashboard
> a turma já viu ontem; o prompt 6 é o fechamento e não pode cair.


---

## Se der errado ao vivo

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| `Circular reference detected in calculated field: receita` | A measure se chama igual à coluna que ela soma | Renomeie a measure: `Receita Total` somando `receita`. `Receita` sobre `receita` referencia a si mesma |
| Widget diz "no selected fields to visualize" | `name` do field ≠ `fieldName` do encoding | Os dois têm que ser a mesma string, ex.: `measure(Receita Total)` |
| Widget diz "unsupported widget definition" | Versão errada, ou cor por widget num counter | Counter não aceita cor própria — a cor vem de `theme.fontColor` |
| Dashboard sobe mas os dados não aparecem | A query prefixou catálogo/schema | `FROM fato_vendas`, sem prefixo |
| Clicar num gráfico não filtra os outros | Cada widget tem um dataset próprio | Junte no mesmo dataset |
| Chave duplicada no `bundle validate` | Dois recursos com a mesma chave | Cada recurso do bundle precisa de chave única, mesmo sendo de tipos diferentes |
| `git diff` não mostra nada | O `.lvdash.json` nunca foi commitado | `git add` + `git commit` do bundle antes da aula |
| O link do dashboard parou de funcionar | Ele foi apagado e recriado pelo deploy — o id muda | Pegue o link novo com `databricks bundle summary` |
| `Unable to locate the bundle root` | O comando rodou fora da pasta do bundle | Todo comando de bundle roda de dentro de `rotaperfumes/` |

> **Este é o prompt para cortar se o tempo estourar.** Dashboard a turma já viu
> ontem. O prompt 6 é o fechamento e não pode cair.

**Tempo medido:** o JSON é grande — conte ~3 minutos de escrita, contra ~40s de
deploy. É o prompt em que você mais vai falar.