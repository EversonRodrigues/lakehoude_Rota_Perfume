# Prompt 2 · O app — a fila dos 200 na tela

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<HOST_DO_WORKSPACE>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).


**Slides que acompanham:** 25 a 33 (divisor *"Uma URL"*, o que é Databricks
Apps, dashboard × Genie × app, o app é um usuário do UC, os tipos que vêm do
catálogo).

**Entrega:** o app no ar, com os quatro números da semana, os 200 contatos
filtráveis por vendedor e o Genie do prompt 1 embutido. **Deploy nº 2.**

> Este é o prompt mais longo da noite, e o único com **vários minutos de tela
> parada**. Prepare a fala: o primeiro `apps deploy` cria o compute do zero.

---

## O ambiente, conferido hoje

Rodado contra `lakehouse_rotaperfume` no workspace `<HOST_DO_WORKSPACE>`, profile
`<PERFIL>`, warehouse `<WAREHOUSE_ID>`.

| Fonte | O que o app lê dela |
|---|---|
| `gold.fila_semanal` | 200 linhas · **36** vendedores · maior score **0,982** |
| `gold.modelo_metricas` | `lift_top200` **4,15** · `acertos_top200` **84** · `taxa_base` 0,1012 |
| `gold.retorno_ligacao` | criada no prompt 1, **vazia** — os KPIs de retorno voltam zero |
| `gold.dim_cliente` | achar pela razão social o cliente que não está na fila |
| Genie `Rota Perfume · Direção` | criado no prompt 1 — é o que entra na aba *Perguntar* |

`databricks apps list` volta **vazio**: não há nenhum app no workspace. O
warehouse precisa estar **ligado** antes de começar — o typegen depende dele.

> **Divergência com o material original.** O roteiro do curso foi medido em
> outro workspace e traz profile `<PERFIL>`, warehouse
> `<WAREHOUSE_ID>`, 35 vendedores, R$ 582.799,50, lift 4,25 e 86 acertos.
> Aqui os números são os da tabela acima. O pipeline é o mesmo e o modelo é
> determinístico — o que muda é o ambiente. **Rode e leia o seu.**

---

## O que mostrar antes

**1 · A tela que o diretor tem hoje**

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
databricks warehouses start <WAREHOUSE_ID> --profile <PERFIL>
```

> *"Vou explicar daqui a pouco por que isso não é frescura."*

---

**Enquanto ele trabalha, você explica:**

- **O app é um usuário do Unity Catalog.** Ele nasce com um *service principal*
  próprio, e esse usuário não tem permissão nenhuma. Declarar o warehouse com
  `CAN_USE` dá acesso ao **compute**, não ao **dado**. É o erro nº 1 de
  Databricks Apps, e a tela que ele produz é a pior possível: carrega, não
  quebra, e mostra vazio. Conferido neste workspace: `SHOW GRANTS ON SCHEMA
  lakehouse_rotaperfume.gold` voltava **vazio** antes dos três `GRANT`.
- **Os tipos vêm do catálogo, e é aqui que o prompt 1 se paga.** O
  `npm run typegen` descreve cada query no warehouse e escreve o TypeScript —
  trazendo junto o `COMMENT` de cada coluna como documentação no editor:

  ```ts
  /** Probabilidade de compra nos proximos 7 dias, vinda de gold.score_propensao. */
  score: number;
  ```

  Aquelas 65 colunas sem COMMENT que a auditoria obrigou a preencher **viram
  isto**. Metadado não é documentação para humano ler: é o que o agente lê para
  escolher a coluna e o que aparece para quem escreve a tela.
- **Nenhuma query mora dentro do React.** Toda leitura é um arquivo `.sql` em
  `config/queries/`, e o nome do arquivo é a chave. E o nome decide mais do que
  parece: **`x.sql` roda como o service principal; `x.obo.sql` roda como o
  usuário logado.** É o arquivo, não a chamada, que define a identidade.
- **Por que vários minutos.** O primeiro deploy provisiona compute, instala
  dependência e faz build. O segundo é bem mais rápido. Deploy de app não é
  deploy de bundle — e é por isso que ele tem ciclo próprio.

---

## O prompt

```
Crie um Databricks App para a direção comercial da Rota Perfume, em
rotaperfume-direcao/ na raiz do repositório — irmão de rotaperfumes/, porque
ele tem deploy próprio e não entra no bundle do lakehouse. Ele lê o que as
noites 2 e 3 produziram; nenhuma tabela nova.

1. O SCAFFOLD

   Ligue o warehouse ANTES — é regra do próprio manifest do plugin analytics,
   e sem ele o typegen degrada:

   databricks warehouses start <WAREHOUSE_ID> --profile <PERFIL>

   databricks apps init --name rotaperfume-direcao \
     --features analytics,genie \
     --set analytics.sql-warehouse.id=<WAREHOUSE_ID> \
     --set genie.genie-space.id=<o id do space "Rota Perfume · Direção"> \
     --set "genie.genie-space.name=Rota Perfume · Direção" \
     --description "A fila dos 200 na tela do diretor" \
     --run none --profile <PERFIL>

   Pegue o id do space com `databricks bundle summary --target dev` dentro de
   rotaperfumes/, ou com `databricks genie list-spaces`. NÃO invente o id.

   Depois do init, configure o mapa `spaces` do plugin genie com um alias
   explícito — mas mantenha o id vindo do ambiente, senão o app deixa de ser
   portável entre workspaces.

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
                     cliente. Parâmetro de vendedor, onde 'Todos' não filtra
   acompanhamento.sql  por vendedor: na_fila, trabalhados e a contagem de
                     cada status

   CONTE VENDEDOR POR vendedor_id, NUNCA POR NOME, e filtre por id também:
   esta base tem nome repetido — 36 vendedores por id contra 35 por nome. Quem
   filtra por nome junta a carteira de duas pessoas numa lista só.

   E o filtro tem uma armadilha de ANSI: a coluna vendedor_id é INT e o
   sentinel é o texto 'Todos'. Comparar os dois faz o DBSQL tentar converter
   'Todos' para número e ABORTAR com CAST_INVALID_INPUT — o OR não protege.
   Ponha o CAST do lado da coluna: CAST(f.vendedor_id AS STRING) = :param.

   Anote os parâmetros com -- @param e dê valor de exemplo (= Todos), senão o
   typegen não consegue descrever a query.

   Rode `npm run typegen` com o WAREHOUSE LIGADO e me mostre a saída. Se
   aparecer OFFLINE ou "degraded", pare: os tipos saem como {} e o tsc quebra
   longe da causa real. `npm run typegen -- --wait` força esperar em vez de
   degradar.

3. AS TELAS — duas, no menu do topo, em português

   "A semana" (rota /):
     - quatro cartões no topo: contatos da semana (com o número de
       vendedores), receita esperada em reais marcada como ESTIMATIVA,
       conversão prevista (acertos_top200/contatos em %) com a taxa base ao
       lado como comparação, e já trabalhados (com quantos viraram pedido)
     - um Select com os vendedores, mais a opção "Todos os vendedores".
       Quando um nome se repetir, ponha o id no rótulo — duas opções
       visualmente idênticas não ajudam ninguém
     - a tabela da fila: ordem, cliente (razão social + cidade/UF + ticket),
       vendedor, chance em %, motivo e sugestão

   "Perguntar" (rota /perguntar):
     - o GenieChat do space do prompt 1
     - o e-mail de quem está logado, lido de uma rota /api/quem-sou que
       devolve o header x-forwarded-email
     - um aviso permanente de que a resposta é gerada por IA, que traz o SQL
       que a produziu, e de QUEM executa a consulta

   A aba Acompanhamento fica para o prompt 3 — mas escreva acompanhamento.sql
   agora, porque é ele que ela vai ler.

   Toda tela precisa tratar os quatro estados: carregando (Skeleton), vazio
   (Empty, com uma frase útil — explique que a fila é global), erro (Alert,
   nunca painel em branco) e o dado.

   Formate em português: R$ com toLocaleString('pt-BR'), score como
   porcentagem inteira. Ninguém decide ligação lendo 0.9740085224443632.

   ATENÇÃO, e isto vale para TODA a tela: o warehouse devolve número como
   STRING no JSON, mesmo que o tipo gerado diga `number`. Passe por Number()
   antes de formatar ou somar — senão toLocaleString devolve a string intacta
   (R$ some e aparece 556423.4988012867) e "7" + "12" vira "712".

   Deixe o estado do filtro no componente PAI. O prompt 3 vai precisar forçar
   a remontagem da lista depois de gravar um retorno, e useAnalyticsQuery não
   tem refetch.

4. AS PERMISSÕES — sem isso o app sobe e mostra tela vazia

   Depois do primeiro deploy, leia o service principal do app com
   `databricks apps get rotaperfume-direcao -o json` (campo
   service_principal_client_id) e conceda:

     GRANT USE CATALOG ON CATALOG lakehouse_rotaperfume TO `<sp>`
     GRANT USE SCHEMA  ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`
     GRANT SELECT      ON SCHEMA  lakehouse_rotaperfume.gold TO `<sp>`

   Leia o id, não copie de lugar nenhum: ele muda a cada app criado.

5. SUBA E ME MOSTRE A URL

   databricks apps validate --profile <PERFIL>
   databricks apps deploy -t default --profile <PERFIL>

   O target chama `default`, não `dev`. E é `apps deploy`, não
   `bundle deploy`: um bundle deploy cria o app parado, sem URL.
```

---

## Como verificar a feature

**1 · O app está de pé, e a URL existe**

```bash
databricks apps get rotaperfume-direcao --profile <PERFIL> -o json | \
  python -c "import json,sys; d=json.load(sys.stdin); print(d['url']); print(d['app_status'], d['compute_status'])"
# app_status RUNNING · compute_status ACTIVE
```

**2 · Os quatro números da tela batem com o banco**

Abra o app ao lado do SQL Editor e confira **na frente da sala**:

```sql
SELECT COUNT(*)                            AS contatos,          -- 200
       COUNT(DISTINCT vendedor_id)         AS vendedores,        -- 36
       ROUND(SUM(score * ticket_medio), 2) AS receita_esperada   -- 556423.71
FROM   lakehouse_rotaperfume.gold.fila_semanal;

SELECT acertos_top200, ROUND(lift_top200,2) AS ganho, ROUND(taxa_base,4) AS base
FROM   lakehouse_rotaperfume.gold.modelo_metricas
ORDER  BY versao DESC LIMIT 1;                                   -- 84 · 4,15 · 0,1012
```

> **Conversão prevista de 42% contra 10,1% às cegas.** É o número que justifica
> o projeto inteiro, e ele agora está no topo de uma página que o diretor abre
> sozinho.

Repare no `COUNT(DISTINCT vendedor_id)`: por nome ele volta **35**, e some com
uma pessoa. É a mesma armadilha que a fila e o Genie já carregam.

**3 · O primeiro registro é zero, e isso é o certo**

O cartão *Já trabalhados* mostra **0** e a frase *"ninguém registrou retorno
ainda"*. Ninguém ligou. É o gancho do prompt 3.

**4 · O filtro por vendedor**

Escolha *Débora Souza* (id 21): **11 contatos**, o maior número da fila.

> **O roteiro original manda "escolher um vendedor com poucos contatos e
> mostrar o estado vazio". Isso não acontece aqui** — o filtro é alimentado
> pela própria `fila_semanal`, então todo vendedor da lista tem pelo menos um
> contato (o menor tem exatamente 1). O `Empty` continua no código como defesa,
> mas para a demo use o vendedor de 1 contato. Se quiser o estado vazio de
> verdade em aula, alimente o filtro de `silver.vendedores`: aí os vendedores
> fora da fila aparecem e devolvem vazio, e a frase *"a fila é global"* fica
> muito mais eloquente.

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
| typegen mostra `OFFLINE` / `degraded` | warehouse parado, ou frio na primeira chamada | `databricks warehouses start`; depois `npm run typegen -- --wait`, que espera em vez de degradar |
| `tsc` reclama de `{}` como tipo | typegen degradado antes | Mesma coisa — o erro aparece longe da causa |
| `CAST_INVALID_INPUT` ao filtrar por vendedor | coluna INT comparada com o sentinel `'Todos'`; o `OR` **não** faz curto-circuito | `CAST(vendedor_id AS STRING) = :param`. O typegen NÃO pega isso: `DESCRIBE` não executa |
| O filtro mostra dois vendedores idênticos | dois vendedores têm o mesmo nome | Chave e rótulo por `vendedor_id` |
| `dev: no such target` | o bundle do app usa `default` | `-t default` |
| App criado mas parado, sem URL | rodou `bundle deploy` | `databricks apps deploy` |
| `failed to acquire deployment lock` | dois deploys ao mesmo tempo | Espere o primeiro terminar |
| `Unexpectedly failed to update app's compute size` | erro transitório do Free Edition | Rode o `apps deploy` de novo |
| O chat do Genie não carrega | o `alias` do `<GenieChat>` não bate com o mapa `spaces` do servidor | Os dois têm que usar a mesma chave |
| Aparece `556423.4988012867` na tela | o valor chegou como string; `toLocaleString` não formatou | `Number(v)` antes de formatar. O tipo diz `number`, o runtime entrega `string` |
| Uma soma dá `712` em vez de `19` | concatenação de strings | Mesmo motivo: `Number()` antes de somar |
| Duas colunas escrevem uma por cima da outra | a tabela não tem largura por coluna | `table-fixed` + `w-[..]` em cada `TableHead`, e `whitespace-normal break-words` nas células |
| `eslint` reprova `set-state-in-effect` no `App.tsx` do template | o scaffold sincroniza o menu mobile com `useEffect` | Renderize o `Sheet` só quando `isMobile`: ao desmontar, o estado vai junto |
| `eslint` acusa erro em `shared/appkit-types/` | são arquivos gerados, marcados "DO NOT EDIT" | Ignore o diretório no `eslint.config.js` |
