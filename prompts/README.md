# Os prompts

Este projeto foi construído conversando com um agente de IA. Cada arquivo aqui é
um **prompt de aula**: o enunciado de uma entrega, com o contexto que o agente
precisa, o que tem de ser verdade no fim e as armadilhas conhecidas.

Eles estão aqui por dois motivos. O primeiro é histórico — dá para reconstruir o
projeto inteiro do zero seguindo a ordem. O segundo é prático: **são um molde**.
A estrutura de um prompt bom (entrega, contexto, critério de aceite, armadilha)
é reaproveitável em qualquer projeto, e é isso que a seção
[Reusar em outro projeto](#reusar-em-outro-projeto) explica.

---

## As variáveis

Os prompts não trazem o endereço de nenhum workspace. Onde apareceria um valor
que depende de quem está rodando, há um **marcador**. Troque os três antes de
colar:

| Marcador | O que é | Como descobrir |
|---|---|---|
| `<PERFIL>` | Nome do perfil da CLI, em `~/.databrickscfg` | `databricks auth profiles` |
| `<WAREHOUSE_ID>` | SQL Warehouse que roda as consultas | `databricks warehouses list --profile <PERFIL>` |
| `<HOST_DO_WORKSPACE>` | URL do workspace, com `https://` | aparece em `databricks auth profiles` |
| `<SEU_EMAIL>` | Conta que faz o deploy | `databricks current-user me --profile <PERFIL>` |
| `<JOB_ID>` | Id do `rotaperfume_pipeline` no seu workspace | `databricks bundle summary --target dev --profile <PERFIL>` |
| `<GENIE_SPACE_ID>` | Id de um Genie space | `databricks genie list-spaces --profile <PERFIL>` |

`<HOST_DO_WORKSPACE>` e `<SEU_EMAIL>` aparecem pouco: quase tudo se resolve com
`--profile`, porque o perfil já carrega o host. Essa é a razão de **todo comando
deste projeto passar `--profile` explicitamente** em vez de confiar no perfil
padrão — é o que mantém o endereço do workspace fora do repositório.

---

## A ordem

As noites são cumulativas: cada uma assume que a anterior está de pé.

### Noite 2 — engenharia de dados

De dez CSVs a um lakehouse com teste. Cinco entregas, cinco deploys.

| | Prompt | Entrega |
|---|---|---|
| 1 | [01-raw.md](noite-2-engenharia-de-dados/01-raw.md) | O catálogo vira código; os CSVs chegam ao Volume; o job ganha a tarefa de conferência |
| 2 | [02-bronze.md](noite-2-engenharia-de-dados/02-bronze.md) | Arquivo vira tabela — tudo STRING — e a contagem tem que bater |
| 3 | [03-silver.md](noite-2-engenharia-de-dados/03-silver.md) | A limpeza com contrato: tipos, constraints, e receita que não se move |
| 4 | [04-gold.md](noite-2-engenharia-de-dados/04-gold.md) | Dimensões, fato e marts, mais 9 testes que interrompem o job |
| 5 | [05-dashboard.md](noite-2-engenharia-de-dados/05-dashboard.md) | O dashboard AI/BI como código, deployado pelo bundle |

> **E a noite 1?** Aconteceu em outro repositório — foi a noite de clicar na
> interface, para depois ter contra o que comparar. Os prompts daqui a
> referenciam ("o dashboard da noite 1", "o número medido na noite 1") e o
> projeto não depende dela.

### Noite 3 — machine learning

[Visão geral](noite-3-machine-learning/00-visao-geral.md) · a pergunta da noite é
*"quais 200?"*

| | Prompt | Entrega |
|---|---|---|
| 1 | [01-features.md](noite-3-machine-learning/01-features.md) | 20 features por cliente, com corte temporal — uma função para treino e escore |
| 2 | [02-modelo.md](noite-3-machine-learning/02-modelo.md) | Baselines, o modelo, MLflow e o registro no Unity Catalog |
| 3 | [03-fila-e-agente.md](noite-3-machine-learning/03-fila-e-agente.md) | A fila dos 200, as funções SQL e o Genie comercial |
| 4 | [04-revisao-do-modelo.md](noite-3-machine-learning/04-revisao-do-modelo.md) | A auditoria depois do deploy: a faixa que não informava nada e a sugestão sem estoque |

Para refazer a noite do zero: [99-limpar.md](noite-3-machine-learning/99-limpar.md)
e o script [99-limpar.sh](noite-3-machine-learning/99-limpar.sh).

### Noite 4 — Genie e app

[Visão geral](noite-4-genie-e-app/00-visao-geral.md) · a pergunta da noite é
*"e quem não escreve SQL?"*

| | Prompt | Entrega |
|---|---|---|
| 1 | [01-genie.md](noite-4-genie-e-app/01-genie.md) | O caminho de volta: `retorno_ligacao`, o Genie da direção, a auditoria de metadado |
| 2 | [02-app.md](noite-4-genie-e-app/02-app.md) | O Databricks App: a fila dos 200 na tela do diretor |
| 3 | [03-retorno.md](noite-4-genie-e-app/03-retorno.md) | O ciclo se fecha: a tela de acompanhamento e a única rota de escrita |
| 4 | [04-estilo-de-resposta.md](noite-4-genie-e-app/04-estilo-de-resposta.md) | O contrato de formato das respostas do Genie — bullets, procedência e a barra no resultado |

Scripts: [99-limpar.sh](noite-4-genie-e-app/99-limpar.sh) desfaz a noite inteira;
[99-limpar-retornos.sh](noite-4-genie-e-app/99-limpar-retornos.sh) apaga só as
linhas de teste de `gold.retorno_ligacao`, sem derrubar a tabela.

---

## Reusar em outro projeto

O que torna estes prompts reaproveitáveis não é o domínio — perfume, vendedor,
carteira — é a **forma**. Todo prompt daqui tem as mesmas quatro partes, e é isso
que vale copiar:

1. **A entrega, em uma frase, com o número do deploy.** "Os 10 CSVs do Volume
   viram 10 tabelas em bronze, e o job falha se a contagem não bater." Sem isso o
   agente decide sozinho onde parar.

2. **O contexto que ele não tem como adivinhar.** Nomes de tabela, o formato
   estranho da data, o fato de dois vendedores terem o mesmo nome. É a parte mais
   longa e a que mais economiza retrabalho.

3. **O critério de aceite, numérico.** "`SUM(valor_liquido)` tem que dar
   102.303.828,05 nas duas camadas." Um critério que se verifica sozinho é a
   diferença entre revisar o código e confiar nele.

4. **A armadilha conhecida, com a razão.** "Não use `to_date`: o warehouse roda
   em modo ANSI e uma data malformada **aborta a query** em vez de devolver
   NULL." Dizer só "use `try_to_date`" faz o agente obedecer; dizer o porquê faz
   ele acertar no caso seguinte, que você não previu.

Para adaptar ao seu projeto: troque os marcadores da tabela acima, troque os
nomes de tabela e os números do critério de aceite, e **mantenha a estrutura**.
As armadilhas de plataforma (ANSI mode, `raise_error` dentro de `CASE`, variável
que não resolve em `workspace.host`) continuam valendo em qualquer projeto
Databricks — essas dá para levar inteiras.
