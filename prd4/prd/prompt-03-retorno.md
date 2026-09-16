# Prompt 3 · O retorno — o ciclo se fecha

**Slides que acompanham:** 34 a 41 (divisor *"O caminho de volta"*, o dado que
sai e não volta, o retorno é o rótulo, botão × contrato, o GRANT escopado, o
teste do ciclo em sete passos e o antes/depois da mesma query).

**Entrega:** os quatro botões que gravam, a aba *Acompanhamento* e a primeira
linha de `gold.retorno_ligacao` escrita ao vivo. **Deploy nº 3 — o último.**

> **É o melhor momento da noite e ele acontece aqui.** Clique em *Vendeu*,
> volte para o SQL Editor, rode um `SELECT` e mostre a linha. O dado saiu do
> pipeline, foi para a tela, e voltou.

---

## O ambiente, conferido hoje

| Fonte | Estado |
|---|---|
| `gold.retorno_ligacao` | existe desde o prompt 1, **0 linhas** |
| O app | no ar, lendo a fila — mas só lendo |
| Service principal do app | tem `SELECT` na gold. **Não tem `MODIFY`** |

---

## O que mostrar antes

**1 · O que o projeto ainda não sabe**

```sql
-- A pergunta que nem o Genie nem o dashboard nem o app respondem hoje:
SELECT COUNT(*) FROM lakehouse_rotaperfume.gold.retorno_ligacao;   -- 0
```

> *"O modelo diz que 86 dos 200 vão comprar. Alguém aqui sabe se ele acertou?
> Não. Não porque a conta é difícil — porque o dado nunca voltou."*

**2 · O desenho que a sala precisa entender antes do código**

Desenhe no quadro, ou no slide:

```
   pipeline  →  score  →  fila  →  ligação  →  ???
                  ↑                              │
                  └──────────────────────────────┘
                     é este pedaço que falta
```

> *"O que o vendedor responde hoje é **o rótulo de treino da semana que vem**.
> A noite 3 treinou com `comprou_em_7d` calculado do histórico de pedidos.
> Daqui a um mês, o modelo pode treinar com o que o time efetivamente
> respondeu — inclusive sobre quem não comprou **porque ninguém ligou**."*

**3 · A pergunta de permissão**

> *"O app vai escrever numa tabela da gold. Que permissão eu dou para ele?"*

A resposta que aparece é "acesso de escrita na gold". E aí:

> *"`MODIFY` no schema inteiro é o app podendo alterar `fato_vendas`. O
> `GRANT` certo é `MODIFY` **em uma tabela só** — a que ele é dono do dado."*

---

**Enquanto ele trabalha, você explica:**

- **Leitura e escrita não usam o mesmo caminho.** Toda leitura continua sendo
  um arquivo `.sql` tipado. A escrita é uma rota `POST` — uma só, com o
  conjunto de valores fechado. Se o front puder mandar `status` livre, em três
  semanas a tabela tem "vendeu", "Vendeu", "vendido" e "VENDEU".
- **A validação está no servidor, não no botão.** Os quatro botões existem para
  a pessoa; o `enum` no servidor existe para o dado. Botão é interface, não
  contrato.
- **Quem clicou fica gravado.** `registrado_por` vem do header
  `x-forwarded-email`, que o Databricks Apps injeta. Sem isso, ninguém sabe
  quem disse que vendeu.
- **A tela não se atualiza sozinha.** `useAnalyticsQuery` não tem `refetch`:
  depois de gravar é preciso mudar a chave do cache. A saída é um parâmetro que
  **não filtra nada** — o dado precisa ser pedido de novo, não filtrado de
  novo.

---

## O prompt

```
Continue o app rotaperfume-direcao. Ele lê a fila; agora ele precisa registrar
o que aconteceu na ligação.

1. A ROTA QUE ESCREVE — uma só, em server/server.ts, dentro de onPluginsReady

   POST /api/retorno, com o corpo validado por Zod ANTES de tocar no banco:
     cliente_id  int (use z.coerce.number(): a tela manda o id que veio do
                 warehouse, e ele chega como STRING mesmo tipado como number)
     vendedor    string não vazia
     status      enum: vendeu | vai_pensar | sem_interesse | nao_atendeu
     comentario  string, no máximo 500 caracteres, opcional
     referencia  string no formato aaaa-mm-dd

   Corpo inválido devolve 400 sem consultar o warehouse. O enum é o contrato:
   é ele que impede a tabela de ter "vendeu", "Vendeu" e "vendido".

   O INSERT vai por
   getExecutionContext().client.statementExecution.executeStatement, com
   warehouse_id vindo do próprio contexto, e TODO valor passado como
   parameters — nunca concatenado na string do SQL.

   registrado_por sai do header x-forwarded-email (com um valor local de
   desenvolvimento como reserva), registrado_em de current_timestamp().

   Mantenha também GET /api/quem-sou, que a aba Perguntar já usa.

   NÃO crie endpoint para ler nada: leitura continua sendo arquivo .sql.

2. OS BOTÕES, na tabela da aba "A semana"

   Uma coluna "Como foi a ligação". Para o cliente sem retorno: um campo de
   texto curto para o comentário e quatro botões — Vendeu, Vai pensar, Sem
   interesse, Não atendeu. O clique grava e desabilita enquanto grava.
   Para quem já tem retorno: mostre o status como Badge e o comentário
   embaixo, sem os botões.

   Se a gravação falhar, mostre um Alert com uma frase em português. Nunca
   engula o erro.

3. A RECARGA — sem isso a tela mente

   useAnalyticsQuery não tem refetch, e o AppKit guarda o resultado da
   consulta. Depois de gravar, a tela continua mostrando o número de antes.

   NÃO resolva isso com um parâmetro falso no SQL (:recarga >= 0). Funciona,
   mas quem estiver com a página aberta de uma versão anterior passa a mandar
   a consulta sem o parâmetro, e o warehouse recusa com UNBOUND_SQL_PARAMETER
   — a tela quebra sozinha depois de um deploy.

   Faça as duas coisas:
   a) desligue o cache de leitura no createApp: cache: { enabled: false }.
      São 200 linhas, e todas mudam quando alguém clica
   b) recarregue em React: guarde filtro e comentários no componente PAI e
      remonte o filho com uma `key` que muda a cada gravação. Remontar refaz
      a consulta, sem inventar coluna nem parâmetro

4. A ABA "Acompanhamento" (rota /acompanhamento)

   Lê acompanhamento.sql:
   - no topo, uma frase: quantos dos 200 foram trabalhados e quantos viraram
     pedido
   - um gráfico de barras por vendedor: trabalhados e vendeu
   - a tabela com o desfecho por vendedor

   Enquanto ninguém registrou nada, mostre um Empty dizendo que o número
   aparece assim que o time marcar o retorno — e que isso vira dado de treino
   da semana que vem. Zero não é erro.

5. A PERMISSÃO DE ESCRITA — escopada em uma tabela só

   GRANT MODIFY ON TABLE lakehouse_rotaperfume.gold.retorno_ligacao TO `<sp>`

   Em TABLE, não em SCHEMA. O app não pode alterar mais nada da gold.

6. Suba:
   databricks apps validate --profile projeto-dados-ia
   databricks apps deploy -t default --profile projeto-dados-ia
```

---

## Como verificar a feature

**1 · O momento da noite: clique, e mostre a linha**

No app, primeiro cliente da fila — *Farmácia Serena*, Goiânia, score **0,974**.
Escreva no comentário *"pediu para ligar quinta"* e clique em **Vendeu**.

Agora, no SQL Editor, com a sala olhando:

```sql
SELECT cliente_id, vendedor, status, comentario, registrado_por, registrado_em
FROM   lakehouse_rotaperfume.gold.retorno_ligacao;
```

A linha está lá, com **o seu e-mail** em `registrado_por`.

> *"Segunda a query quebrou por causa de data em dois formatos. Hoje um clique
> virou uma linha na gold. É o mesmo lugar — o dado deu a volta inteira."*

**2 · O contrato recusa o que não é válido**

```bash
curl -X POST <URL-do-app>/api/retorno \
  -H "Content-Type: application/json" \
  -d '{"cliente_id":2137,"vendedor":"Bruno Souza","status":"talvez","referencia":"2026-08-31"}'
```

Devolve **400** com a lista dos quatro valores aceitos, e **nada** chega ao
warehouse. Botão é interface; o enum é o contrato.

**3 · A tela reflete na hora**

Depois do clique, o cartão *Já trabalhados* vai de **0** para **1**, e o
cliente aparece com o Badge em vez dos botões. Se não mudar, o parâmetro de
recarga não está subindo.

**4 · O Genie do prompt 1 responde sobre o que acabou de acontecer**

Volte para a aba *Perguntar* — ou abra o space direto — e pergunte:

> *"Quantas ligações já foram registradas e quantas viraram pedido?"*

Ele agora responde **1 e 1**. Vinte minutos atrás, respondia que ninguém tinha
registrado nada. **Nenhuma linha de código do Genie mudou** — mudou o dado
embaixo dele.

**5 · Limpe antes de encerrar, se for ensaiar de novo**

```sql
DELETE FROM lakehouse_rotaperfume.gold.retorno_ligacao;
```

---

## Se der errado

| Sintoma | Causa | Saída |
|---|---|---|
| `PERMISSION_DENIED` ao gravar | falta `MODIFY` na tabela | `GRANT MODIFY ON TABLE ... TO \`<sp>\`` — em TABLE, não em SCHEMA |
| Grava, mas a tela não muda | a `key` não mudou, ou o cache está ligado | `cache: { enabled: false }` + `key` que muda a cada gravação |
| `UNBOUND_SQL_PARAMETER: recarga` | o SQL pede um parâmetro que a tela não manda — JS antigo no navegador do usuário | Não use parâmetro falso para furar cache. Se já usou, `Ctrl+Shift+R` resolve o sintoma |
| `registrado_por` sempre igual | rodando local, sem OAuth | Em `npm run dev` não há header. No app publicado, vem o e-mail real |
| O POST devolve 400 sem motivo claro | Zod recusou o corpo | Leia `detalhe` na resposta: ele diz qual campo e o que era esperado |
| Erro de tipo no `executeStatement` | `serviceDatabricksClient` não existe | O contexto expõe `client` e `warehouseId` |
| O POST devolve 400 dizendo que `cliente_id` não é número | a tela mandou `"2137"`, string | `z.coerce.number().int()` no servidor e `Number()` na tela |
| O gráfico do acompanhamento não aparece | ninguém registrou nada ainda | É o estado vazio, e ele está certo. Registre um retorno |
| Deploy falha na primeira tentativa | erro transitório de compute do Free Edition | Rode o `apps deploy` de novo |
