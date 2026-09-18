#!/usr/bin/env bash
# Limpa SÓ a noite 3 e devolve o ambiente ao fim da noite 2.
#
# A noite 2 continua de pé: catálogo, bronze, silver, gold, dashboard e Genie.
# Some apenas o que os três prompts de hoje criaram — para você poder rodar os
# três de novo, do zero, quantas vezes quiser.
#
# Uso:  bash prompts/noite-3-machine-learning/99-limpar.sh <profile> [--apagar]
#       Sem --apagar ele só MOSTRA o que faria.
#
# O que apaga:
#   1. as tabelas de ML da gold — das DUAS versões da noite 3
#   2. as views de decisão (DROP TABLE não derruba view)
#   3. as funções-ferramenta da gold
#   4. o modelo registrado no Unity Catalog, com todas as versões
#   5. o experimento do MLflow
#   6. o código local: src/ml/ apagado, e pipeline.job.yml e
#      comercial.geniespace.json restaurados do git
#   7. o redeploy, para o job voltar a 12 tarefas e o Genie parar de
#      apontar para tabela que não existe mais
#   8. a verificação: prova na tela que não sobrou nada — e sai com erro
#      se sobrou
set -euo pipefail

PROFILE="${1:?uso: bash prompts/noite-3-machine-learning/99-limpar.sh <profile> [--apagar]}"
CONFIRMA="${2:-}"
CATALOGO="${CATALOGO:-lakehouse_rotaperfume}"

AULA="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$(cd "$AULA/../aula-02-engenharia-de-dados/rotaperfume" && pwd)"

# Cobre as DUAS versões da noite 3: a de 3 prompts (atual) e a de 6 prompts
# (anterior), porque o workspace pode estar em qualquer uma das duas.
TABELAS=(features_treino features_cliente score_propensao fila_semanal
         modelo_metricas calibragem_holdout
         modelo_importancia modelo_promocoes modelo_validacao)
VIEWS=(carteira_do_dia oportunidade_por_faixa receita_em_risco)
FUNCOES=(priorizar_carteira contexto_cliente sugerir_produtos checar_disponibilidade)
MODELO="$CATALOGO.gold.propensao_compra"
TAREFAS=(ml_features ml_modelo ml_fila
         ml_treino ml_promocao ml_score ml_testes ml_carteira_do_dia)

echo "profile:   $PROFILE"
echo "catálogo:  $CATALOGO   (a noite 2 NÃO é tocada)"
echo "tabelas:   ${TABELAS[*]}"
echo "views:     ${VIEWS[*]}"
echo "funções:   ${FUNCOES[*]}"
echo "tarefas:   ${TAREFAS[*]}"
echo "modelo:    $MODELO"
echo "bundle:    $BUNDLE"
echo

if [ "$CONFIRMA" != "--apagar" ]; then
  echo "Simulação. Nada foi apagado."
  echo "Para apagar de verdade:  bash prompts/noite-3-machine-learning/99-limpar.sh $PROFILE --apagar"
  exit 0
fi

sql() { echo "$1" | databricks experimental aitools tools query --profile "$PROFILE" || true; }

echo "→ dropando as tabelas de ML..."
for t in "${TABELAS[@]}"; do sql "DROP TABLE IF EXISTS $CATALOGO.gold.$t"; done

echo "→ dropando as views de decisão..."
for v in "${VIEWS[@]}"; do sql "DROP VIEW IF EXISTS $CATALOGO.gold.$v"; done

echo "→ dropando as funções-ferramenta..."
for f in "${FUNCOES[@]}"; do sql "DROP FUNCTION IF EXISTS $CATALOGO.gold.$f"; done

# O delete do modelo RECUSA enquanto houver versão viva:
#   "Function ... is not empty. The function has 2 model versions(s)"
# Por isso as versões saem primeiro, uma a uma.
echo "→ apagando as versões do modelo..."
# O `|| true` no fim é obrigatório: sem modelo, o list falha e o grep não acha
# nada — e com `set -e` + `pipefail` isso mataria o script justamente no caso
# em que não há o que apagar.
VERSOES=$(databricks model-versions list "$MODELO" --profile "$PROFILE" -o json 2>/dev/null \
          | grep -oE '"version": [0-9]+' | grep -oE '[0-9]+' | sort -u || true)
for v in $VERSOES; do
  echo "   versão $v"
  databricks model-versions delete "$MODELO" "$v" --profile "$PROFILE" 2>/dev/null || true
done

echo "→ apagando o modelo registrado..."
databricks registered-models delete "$MODELO" --profile "$PROFILE" 2>/dev/null || \
  echo "   (modelo não existia — segue)"

echo "→ apagando o experimento do MLflow..."
EXP="/Users/$(databricks current-user me --profile "$PROFILE" -o json | python3 -c 'import sys,json;print(json.load(sys.stdin)["userName"])')/rotaperfume"
databricks workspace delete "$EXP" --recursive --profile "$PROFILE" 2>/dev/null || \
  echo "   (pasta $EXP não existia — segue)"

# ── 6. o código local ─────────────────────────────────────────────────
#
# A ORDEM IMPORTA: apagar no workspace ANTES de restaurar os arquivos, e o
# deploy só DEPOIS dos dois. Invertendo, o deploy roda com o geniespace.json
# ainda citando fila_semanal e morre com PERMISSION_DENIED numa mensagem que
# não explica nada.
#
# Restaurar do git em vez de editar YAML e JSON: é exato por construção e pega
# até o que estes scripts não previram. A âncora é a tag noite-2-pronta, que
# sobrevive a um commit feito no meio da aula; sem ela, cai para HEAD.
echo "→ removendo o código local da noite 3..."
rm -rf "$BUNDLE/src/ml"

REF=$(git -C "$BUNDLE" rev-parse --verify -q noite-2-pronta || echo HEAD)
echo "→ restaurando pipeline.job.yml e comercial.geniespace.json de $REF..."
git -C "$BUNDLE" restore --source="$REF" -- \
    resources/pipeline.job.yml resources/comercial.geniespace.json

# ── 7. o redeploy ─────────────────────────────────────────────────────
echo "→ redeployando o bundle..."
SAIDA=$(cd "$BUNDLE" && databricks bundle deploy --target dev --profile "$PROFILE" 2>&1) || true
echo "$SAIDA" | tail -4
if grep -q "destructive actions" <<< "$SAIDA"; then
  echo
  echo "ABORTADO. O deploy quer apagar um recurso que NÃO é da noite 3 —"
  echo "provavelmente o dashboard da noite 2. NÃO passe --auto-approve."
  echo "Chame o Claude Code com a saída acima."
  exit 1
fi

# ── 8. a verificação ──────────────────────────────────────────────────
#
# Limpeza que não prova que limpou não serve — é o mesmo princípio dos testes
# que quebram o job.
echo
echo "── conferindo ────────────────────────────────────────────────────"
FALHAS=0
conferir() {  # conferir "rótulo" "esperado" "obtido"
  if [ "$2" = "$3" ]; then printf "  ok    %-38s %s\n" "$1" "$3"
  else printf "  FALHA %-38s esperado %s, veio %s\n" "$1" "$2" "$3"; FALHAS=$((FALHAS+1)); fi
}
consulta() { databricks experimental aitools tools query "$1" --profile "$PROFILE" 2>/dev/null \
             | python3 -c "import sys,json;d=json.load(sys.stdin);print(list(d[0].values())[0] if d else 0)" 2>/dev/null || echo "?"; }

RESTO=$(consulta "SELECT COUNT(*) AS n FROM $CATALOGO.information_schema.tables
                  WHERE table_schema='gold' AND (table_name LIKE '%features%'
                     OR table_name LIKE '%score%' OR table_name LIKE '%fila%'
                     OR table_name LIKE '%modelo%' OR table_name LIKE '%carteira_do_dia%'
                     OR table_name LIKE '%oportunidade_por_faixa%'
                     OR table_name LIKE '%receita_em_risco%'
                     OR table_name LIKE '%calibragem%')")
conferir "tabelas/views da noite 3" "0" "$RESTO"

FUNCS=$(consulta "SELECT COUNT(*) AS n FROM $CATALOGO.information_schema.routines
                  WHERE routine_schema='gold'")
conferir "funções na gold" "0" "$FUNCS"

MODELOS=$(databricks registered-models list --catalog-name "$CATALOGO" --schema-name gold \
          --profile "$PROFILE" -o json 2>/dev/null | grep -c '"full_name"' || true)
conferir "modelos registrados" "0" "${MODELOS:-0}"

TAREFAS_N=$(grep -c "^        - task_key:" "$BUNDLE/resources/pipeline.job.yml" || true)
conferir "tarefas no pipeline.job.yml" "12" "$TAREFAS_N"

# A gold só precisa estar DE PÉ para a noite 3 começar. Se ela está íntegra é
# assunto do teste 1 da noite 2 (receita gold = receita silver), que roda no
# job — não desta limpeza. Mas vale avisar, porque começar a noite 3 sobre uma
# gold divergente é construir feature em cima de venda que sumiu.
LINHAS=$(consulta "SELECT COUNT(*) AS n FROM $CATALOGO.gold.fato_vendas")
[ "${LINHAS:-0}" -gt 100000 ] 2>/dev/null \
  && conferir "gold.fato_vendas de pé" "sim" "sim" \
  || conferir "gold.fato_vendas de pé" "sim" "NÃO ($LINHAS linhas)"

DIVERGENCIA=$(consulta "SELECT ROUND(ABS(
    (SELECT SUM(receita) FROM $CATALOGO.gold.fato_vendas) -
    (SELECT SUM(valor_liquido) FROM $CATALOGO.silver.pedidos WHERE NOT cancelado)), 2) AS n")
if [ "$DIVERGENCIA" != "0" ] && [ "$DIVERGENCIA" != "0.0" ] && [ "$DIVERGENCIA" != "?" ]; then
  echo "  AVISO receita gold x silver diverge em R\$ $DIVERGENCIA"
  echo "        O teste 1 da noite 2 vai quebrar o job. Isto não é da noite 3."
fi

VIEWS_N=$(consulta "SELECT COUNT(*) AS n FROM $CATALOGO.information_schema.views
                    WHERE table_schema='gold'")
conferir "views de negócio na gold" "6" "$VIEWS_N"

echo
if [ "$FALHAS" -gt 0 ]; then
  echo "$FALHAS checagem(ns) falharam. NÃO comece a noite 3 assim."
  exit 1
fi
echo "Zerado e conferido. Os três prompts têm que reconstruir tudo do nada."
echo "Comece por prd/prompt-01-features.md."