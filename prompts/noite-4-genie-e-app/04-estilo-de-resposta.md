# Prompt 4 · O estilo da resposta — bullets, procedência e o gráfico que sempre aparece

> **Antes de colar:** troque `<PERFIL>`, `<WAREHOUSE_ID>` e `<GENIE_SPACE_ID>`
> pelos valores do seu ambiente — a tabela está em
> [prompts/README.md](../README.md#as-variáveis).

**Entrega:** um contrato de formato de resposta, igual nos dois Genie spaces,
carregado na única entrada de `text_instructions` de cada payload.

> A pergunta que originou isto foi simples: *"queria que as respostas do Genie
> viessem mais atrativas, com bullets e pequenos gráficos"*. A parte do texto é
> fácil. A parte do gráfico tem uma pegadinha que vale a aula inteira.

---

## A pegadinha: não existe botão de gráfico

**O gráfico aparece quando o RESULTADO tem formato de gráfico.** Não há campo no
`serialized_space` que peça um. Quem decide é a consulta que o Genie escreve — e
é por isso que o contrato de estilo tem duas metades, uma sobre o texto e outra
sobre o SQL.

Sobre o SQL:

- **Agregue.** Pergunta de panorama devolve de 3 a 12 linhas, nunca 200. Só
  liste linha a linha quando pedirem a lista.
- **Duas colunas já fazem um gráfico:** um rótulo de texto e um número. Dê ao
  rótulo o nome de negócio (`Vendedor`, `Faixa`), nunca um id.
- `ORDER BY` no número, decrescente, com `LIMIT` explícito. Arredonde.
- Em ranking e distribuição, uma coluna `barra`:

```sql
repeat('█', CAST(ROUND(20.0 * COUNT(*) / MAX(COUNT(*)) OVER (), 0) AS INT)) AS barra
```

Essa é a única "visualização" que aparece **sempre**, inclusive quando a resposta
volta como tabela. Use `█`, não `|`: o pipe quebra a tabela markdown em que ele
é renderizado.

---

## A outra metade: o texto

Genie renderiza markdown, então peça markdown de verdade. Três partes, em toda
resposta:

1. **Primeira linha:** só o número, em negrito, formatado em pt-BR
   (`R$ 556.423,71`, `4,15x`) — nunca `556423.71`.
2. **Dois a quatro bullets** de uma frase: o recorte, a comparação, o que chama
   atenção.
3. **Última linha, em itálico:** a procedência — tabela, filtro e denominador.

Mais duas regras que evitam briga de reunião:

- **Todo percentual com o denominador escrito:** `12% (6 de 50 trabalhadas)`.
- **Abaixo de 30 linhas**, a resposta diz que a amostra é pequena **antes** de
  dar o número.
- Se for estimativa, a palavra aparece na **primeira** linha, não no rodapé.

> É o mesmo contrato de quatro partes do componente `Kpi` do app — valor,
> comparação, destaque, procedência — só que em prosa. Vale a pena reparar: a
> regra é da **organização**, não da tecnologia, e por isso ela se repete em
> lugares que não compartilham uma linha de código.

---

## Uma armadilha do próprio formato

A primeira versão do exemplo `O modelo e bom?` repetia `lift_top200` nas duas
linhas da comparação (fila do modelo / ligação aleatória). O Genie então
escreveu:

> *"O lift_top200 está estável entre as abordagens"*

O que não quer dizer nada: o lift **é a razão entre as duas linhas**, não um
atributo de cada uma. Corrigido deixando o valor só na linha do modelo e `NULL`
na outra. **Uma coluna repetida convida o modelo a comparar o que não se
compara** — a mesma família de erro de colocar `vendeu` ao lado de
`trabalhados`, sendo um subconjunto do outro.

---

## Aplicar

Os dois spaces são gerenciados de formas diferentes, de propósito — e é por isso
que o comando muda:

```bash
# DIREÇÃO — é recurso do bundle (resources/genie-direcao.genie_space.yml)
databricks bundle validate --strict --target dev --profile <PERFIL>
databricks bundle deploy --target dev --profile <PERFIL>

# COMERCIAL — foi criado pela CLI, não é recurso do bundle
databricks genie list-spaces --profile <PERFIL>          # descobre o <GENIE_SPACE_ID>
databricks genie update-space <GENIE_SPACE_ID> --profile <PERFIL> --json @payload.json
```

O `payload.json` é `{"serialized_space": "<o JSON inteiro como STRING>"}` — o
espaço serializado vai **stringificado** dentro do campo, não como objeto.

> **No Windows, monte esse arquivo com Python escrevendo UTF-8 e passe `@arquivo`.**
> Interpolar o JSON na linha de comando quebra com
> `UnicodeEncodeError: 'charmap' codec can't encode character '█'` — o
> console é cp1252 e o `█` não cabe nele.

---

## Conferir com uma pergunta de verdade

```bash
databricks genie start-conversation <GENIE_SPACE_ID> \
  "Como a fila desta semana se distribui por faixa?" --profile <PERFIL> -o json
```

O que voltou depois do contrato no ar:

```
**141 contatos**
- Recorte: semana atual, 200 linhas totais na fila.
- "Muito quente, 4,4x a chance média" representa 70,5% (141 de 200 contatos) e
  concentra a maior parte da receita estimada.
- "Quente, 2,2x a chance média" responde por 29,5% (59 de 200 contatos).
_Fonte: gold.fila_semanal, 200 linhas, fila gerada na semana mais recente._
```

Número em negrito, denominador em todo percentual, procedência no fim, e a faixa
nunca aparecendo sem o múltiplo do lado. **Nenhuma linha de código do app mudou.**

---

## Armadilhas

| Armadilha | Como aparece | O que fazer |
|---|---|---|
| **Pedir "gráfico" nas instruções** | nada muda | o formato quem decide é o `SELECT`; restrinja a consulta |
| **`\|` como caractere de barra** | a tabela markdown quebra | use `█` |
| **`text_instructions` com mais de um item** | API recusa: *must contain at most one item* | funde tudo numa entrada só |
| **Regra de estilo brigando com regra antiga** | "no máximo três frases" impedia bullet | releia a instrução inteira antes de acrescentar |
| **JSON interpolado no shell do Windows** | `UnicodeEncodeError: 'charmap'` | escreva o payload em arquivo UTF-8 e use `--json @arquivo` |
| **Coluna repetida em linhas que se comparam** | *"o lift está estável entre as abordagens"* | valor só onde ele existe; `NULL` no resto |
