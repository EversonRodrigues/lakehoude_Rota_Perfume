# Prompt 2 · O app — a fila dos 200 na tela

**Slides que acompanham:** 25 a 33 (divisor *"Uma URL"*, o que é Databricks
Apps, dashboard × Genie × app, o app é um usuário do UC, os tipos que vêm do
catálogo).

**Entrega:** o app no ar, com os quatro números da semana, os 200 contatos
filtráveis por vendedor e o Genie do prompt 1 embutido. **Deploy nº 2.**

> Este é o prompt mais longo da noite, e o único com **quase quatro minutos de
> tela parada**. Prepare a fala: o primeiro `apps deploy` cria o compute do
> zero e leva **3m44s** medidos.

---

## O ambiente, conferido hoje

| Fonte | O que o app lê dela |
|---|---|
| `gold.fila_semanal` | 200 linhas · 35 vendedores · maior score **0,974** |
| `gold.modelo_metricas` | versão 3 · `lift_top200` 4,25 · `acertos_top200` 86 |
| `gold.retorno_ligacao` | criada no prompt 1, **vazia** — os KPIs de retorno voltam zero |
| Genie `Rota do Perfume · Direção` | criado no prompt 1 — é o que entra na aba *Perguntar* |

`databricks apps list` volta **vazio**: não há nenhum app no workspace. O
warehouse `Serverless Starter Warehouse` (`666be37e3fededf2`) precisa estar
**ligado** antes de começar — o typegen depende dele.

---

## O que mostrar antes

**1 · A tela que o diretor tem hoje**

Abra o SQL Editor e rode a query da fila:

```sql
SELECT vendedor, ordem, razao_social, ROUND(score,2) AS nota, motivo, sugestao
FROM   lakehouse_rotaperfume.gold.fila_semanal
ORDER  BY score DESC;
```

> *"Está certíssimo. Agora imagine mandar isso para o diretor comercial toda
> segunda de manhã. Ele vai pedir para você filtrar por vendedor. Depois vai
> pedir para marcar quem já foi contatado. E na terceira semana ele volta a
> ligar pela intuição."*

**2 · A pergunta que decide o desenho — faça para a sala**

> *"Dashboard, Genie e app leem a mesma tabela. Por que três?"*

| Porta | Para quem | O que só ela faz |
|---|---|---|
| **Dashboard** | quem acompanha número recorrente | agenda, alerta, zero código |
| **Genie** | quem tem pergunta que ninguém previu | responde o que não estava na tela |
| **App** | quem trabalha a lista todo dia | interação e **escrita de volta** |

> **Genie responde. App registra.** A diferença não é tecnologia — é a direção
> do dado. E é por isso que o app é o único dos três que precisa de `MODIFY`.

**3 · Ligue o warehouse, na frente da sala**

```bash
databricks warehouses start 666be37e3fededf2 --profile projeto-dados-ia
```

> *"Vou explicar daqui a pouco por que isso não é frescura."*

---

**Enquanto ele trabalha, você explica:**

- **O app é um usuário do Unity Catalog.** Ele nasce com um *service principal*
  próprio, e esse usuário não tem permissão nenhuma. Declarar o warehouse com
  `CAN_USE` dá acesso ao **compute**, não ao **dado**. É o erro nº 1 de
  Databricks Apps, e a tela que ele produz é a pior possível: carrega, não
  quebra, e mostra vazio.
- **Os tipos vêm do catálogo.** O `npm run typegen` descreve cada query no
  warehouse e escreve o TypeScript. O `COMMENT` que a auditoria da noite 2
  exigiu em toda coluna aparece como documentação dentro do editor:
  `/** Probabilidade de o cliente fazer pedido nos próximos 7 dias. */`.
  **Metadado não é documentação para humano ler** — é o que o agente lê para
  escolher a coluna e o que o editor mostra para quem escreve a tela.
- **Nenhuma query mora dentro do React.** Toda leitura é um arquivo `.sql` em
  `config/queries/`, e o nome do arquivo é a chave. SQL no lugar de SQL,
  interface no lugar de interface.
- **Por que quatro minutos.** O primeiro deploy provisiona compute, instala
  dependência e faz build. O segundo leva **um minuto**. Deploy de app não é
  deploy de bundle — e é por isso que ele tem ciclo próprio.

---

## O prompt

```
Crie um Databricks App para a direção comercial da Rota do Perfume, em
aulas/aula-04-app-e-genie/. Ele lê o que a noite 3 produziu — nenhuma tabela
nova.

1. O SCAFFOLD

   databricks apps init --name rotaperfume-direcao \
     --features analytics,genie \
     --set analytics.sql-warehouse.id=666be37e3fededf2 \
     --set genie.genie-space.id=<o id do space "Rota do Perfume · Direção"> \
     --set genie.genie-space.name="Rota do Perfume · Direção" \
     --description "A fila dos 200 na tela do diretor" \
     --run none --profile projeto-dados-ia

   Pegue o id do space com `databricks bundle summary --target dev` no bundle
   da noite 2, ou com `databricks genie list-spaces`. NÃO invente o id.

2. AS QUERIES, uma por arquivo em config/queries/ — nunca SQL dentro do React

   kpis_semana.sql   contatos, vendedores, receita esperada
                     (SUM(score*ticket_medio)), a referência da fila, mais
                     acertos_top200/lift_top200/taxa_base da ÚLTIMA versão de
                     gold.modelo_metricas (QUALIFY ROW_NUMBER() OVER
                     (ORDER BY versao DESC) = 1) e a contagem de
                     gold.retorno_ligacao
   vendedores.sql    vendedor -> contatos, para alimentar o filtro
   fila.sql          os 200 com todas as colunas de leitura humana (motivo,
                     sugestao), LEFT JOIN com o retorno mais recente de cada
                     cliente. Parâmetro `vendedor`, onde 'Todos' não filtra
   acompanhamento.sql  por vendedor: na_fila, trabalhados e a contagem de
                     cada status

   Anote os parâmetros com -- @param e dê valor de exemplo (= Todos), senão o
   typegen não consegue descrever a query.

   Rode `npm run typegen` com o WAREHOUSE LIGADO e me mostre a saída. Se
   aparecer OFFLINE ou "degraded", pare: os tipos saem como {} e o tsc quebra
   longe da causa real.

3. AS TELAS — três, no menu do topo, em português

   "A semana" (rota /):
     - quatro cartões no topo: contatos da semana (com o número de
       vendedores), receita esperada em reais, conversão prevista
       (acertos_top200/contatos em %) com a taxa base ao lado como
       comparação, e já trabalhados (com quantos viraram pedido)
     - um Select com os vendedores, mais a opção "Todos os vendedores"
     - a tabela da fila: ordem, cliente (razão social + cidade/UF + ticket),
       vendedor, chance em %, motivo e sugestão

   "Perguntar" (rota /perguntar):
     - o GenieChat do space do prompt 1
     - o e-mail de quem está logado, lido de uma rota /api/quem-sou que
       devolve o header x-forwarded-email
     - um aviso permanente de que a resposta é gerada por IA e traz o SQL que
       a produziu

   Toda tela precisa tratar os quatro estados: carregando (Skeleton), vazio
   (Empty, com uma frase útil — para um vendedor sem contatos, explique que a
   fila é global), erro (Alert, nunca painel em branco) e o dado.

   Formate em português: R$ com toLocaleString('pt-BR'), score como
   porcentagem inteira. Ninguém decide ligação lendo 0.9740085224443632.

   ATENÇÃO, e isto vale para TODA a tela: o warehouse devolve número como
   STRING no JSON, mesmo que o tipo gerado diga `number`. Passe por Number()
   antes de formatar ou somar — senão toLocaleString devolve a string intacta
   (R$ some e aparece 582799.4988012867) e "7" + "12" vira "712".

4. AS PERMISSÕES — sem isso o app sobe e mostra tela vazia

   Depois do primeiro deploy, leia o service principal do app com
   `databricks apps get rotaperfume-direcao -o json` (campo
   service_principal_client_id) e conceda:

     GRANT USE CATALOG ON CATALOG lakehouse_rotaperfume TO `<sp>`
     GRANT USE SCHEMA  ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`
     GRANT SELECT      ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`

   Leia o id do workspace, não copie de lugar nenhum: ele muda a cada app.

5. SUBA E ME MOSTRE A URL

   databricks apps validate --profile projeto-dados-ia
   databricks apps deploy -t default --profile projeto-dados-ia

   O target chama `default`, não `dev`. E é `apps deploy`, não
   `bundle deploy`: um bundle deploy cria o app parado, sem URL.
```

---

## Como verificar a feature

**1 · O app está de pé, e a URL existe**

```bash
databricks apps get rotaperfume-direcao --profile projeto-dados-ia -o json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print(d['url']); print(d['app_status'], d['compute_status'])"
# app_status RUNNING · compute_status ACTIVE
```

**2 · Os quatro números da tela batem com o banco**

Abra o app ao lado do SQL Editor e confira **na frente da sala**:

```sql
SELECT COUNT(*)                            AS contatos,          -- 200
       COUNT(DISTINCT vendedor)            AS vendedores,        -- 35
       ROUND(SUM(score * ticket_medio), 2) AS receita_esperada   -- 582799.50
FROM   lakehouse_rotaperfume.gold.fila_semanal;

SELECT acertos_top200, ROUND(lift_top200,2) AS ganho, ROUND(taxa_base,4) AS base
FROM   lakehouse_rotaperfume.gold.modelo_metricas
ORDER  BY versao DESC LIMIT 1;                                   -- 86 · 4,25 · 0,1012
```

> **Conversão prevista de 43% contra 10,1% às cegas.** É o número que justifica
> o projeto inteiro, e ele agora está no topo de uma página que o diretor abre
> sozinho.

**3 · O primeiro registro é zero, e isso é o certo**

O cartão *Já trabalhados* mostra **0**, e a aba *Acompanhamento* — se você já
a construiu — está vazia. Ninguém ligou ainda. É o gancho do prompt 3.

**4 · O filtro por vendedor**

Escolha *Débora Souza*: **12 contatos**, o maior número da fila. Escolha um
vendedor com poucos e mostre o estado vazio explicando que a fila é global.

**5 · A aba Perguntar responde com o SQL à vista**

Pergunte *"quanto vale a fila desta semana?"* dentro do app e mostre o SQL
gerado. **O mesmo Genie do prompt 1, agora dentro do produto.** Uma definição,
duas portas.

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| Toda tela vazia, sem erro visível | o service principal não tem GRANT | Os três `GRANT`. `CAN_USE` no warehouse **não** dá acesso ao dado |
| `PERMISSION_DENIED` nas queries | idem, ou o SP copiado de outro ambiente | Releia com `databricks apps get` |
| typegen mostra `OFFLINE` / `degraded` | warehouse parado | `databricks warehouses start`, rode o typegen de novo |
| `tsc` reclama de `{}` como tipo | typegen degradado antes | Mesma coisa — o erro aparece longe da causa |
| `dev: no such target` | o bundle do app usa `default` | `-t default` |
| App criado mas parado, sem URL | rodou `bundle deploy` | `databricks apps deploy` |
| `failed to acquire deployment lock` | dois deploys ao mesmo tempo | Espere o primeiro terminar |
| `Unexpectedly failed to update app's compute size` | erro transitório do Free Edition | Rode o `apps deploy` de novo. Resolveu na segunda tentativa |
| O chat do Genie não carrega | space id errado no `databricks.yml` | Confira com `databricks genie list-spaces` |
| Aparece `582799.4988012867` na tela | o valor chegou como string; `toLocaleString` não formatou | `Number(v)` antes de formatar. O tipo diz `number`, o runtime entrega `string` |
| Uma soma dá `712` em vez de `19` | concatenação de strings | Mesmo motivo: `Number()` antes de somar |
| Duas colunas escrevem uma por cima da outra | a tabela não tem largura por coluna | `table-fixed` + `w-[..]` em cada `TableHead`, e `whitespace-normal break-words` nas células |
