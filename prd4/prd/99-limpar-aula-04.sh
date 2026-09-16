#!/usr/bin/env bash
# Limpa SÓ a noite 4 e devolve o ambiente ao fim da noite 3.
#
# As noites 2 e 3 continuam de pé: catálogo, pipeline, dashboard, o Genie
# comercial, o modelo e a fila dos 200. Some apenas o que os três prompts de
# hoje criaram — para você poder rodar os três de novo, quantas vezes quiser.
#
# Uso:  bash prd/99-limpar-aula-04.sh <profile> [--apagar]
#       Sem --apagar ele só MOSTRA o que faria.
#
# O que apaga:
#   1. o Databricks App e todo o projeto local dele
#   2. o Genie space da direção
#   3. gold.retorno_ligacao — COM O DADO QUE O TIME REGISTROU
#   4. o SQL e as tarefas gold_retorno_ligacao e auditoria_de_metadado,
#      mais o backfill dos 65 COMMENT da gold, restaurados do git
#   5. o redeploy, para o job voltar a 13 tarefas
#   6. a verificação: prova na tela que não sobrou nada
set -euo pipefail

PROFILE="${1:?uso: bash prd/99-limpar-aula-04.sh <profile> [--apagar]}"
CONFIRMA="${2:-}"
CATALOGO="${CATALOGO:-lakehouse_rotaperfume}"

AULA="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$(cd "$AULA/../rotaperfumes" && pwd)"
APP_DIR="$AULA/rotaperfume-direcao"
APP_NOME="rotaperfume-direcao"

echo "profile:   $PROFILE"
echo "catálogo:  $CATALOGO   (as noites 2 e 3 NÃO são tocadas)"
echo "app:       $APP_NOME  ($APP_DIR)"
echo "genie:     resources/direcao.geniespace.json + genie-direcao.genie_space.yml"
echo "tabela:    $CATALOGO.gold.retorno_ligacao"
echo "tarefa:    gold_retorno_ligacao"
echo "bundle:    $BUNDLE"
echo

echo "→ o que existe hoje em retorno_ligacao:"
echo "SELECT COUNT(*) AS linhas FROM $CATALOGO.gold.retorno_ligacao" \
  | databricks experimental aitools tools query --profile "$PROFILE" 2>/dev/null || \
  echo "   (a tabela não existe)"
echo

if [ "$CONFIRMA" != "--apagar" ]; then
  echo "Simulação. Nada foi apagado."
  echo "ATENÇÃO: com --apagar, o retorno registrado pelo time é PERDIDO."
  echo "Para apagar de verdade:  bash prd/99-limpar-aula-04.sh $PROFILE --apagar"
  exit 0
fi

sql() { echo "$1" | databricks experimental aitools tools query --profile "$PROFILE" || true; }

echo "→ apagando o Databricks App (leva ~20s)..."
databricks apps delete "$APP_NOME" --profile "$PROFILE" 2>/dev/null || \
  echo "   (o app não existia)"

echo "→ apagando o projeto local do app..."
rm -rf "$APP_DIR"

echo "→ apagando a tabela de retorno..."
sql "DROP TABLE IF EXISTS $CATALOGO.gold.retorno_ligacao"

echo "→ removendo o Genie da direção e a tarefa, restaurando do git..."
cd "$BUNDLE"
rm -f resources/direcao.geniespace.json resources/genie-direcao.genie_space.yml
rm -f src/gold/12-retorno-ligacao.sql src/gold/13-auditoria-metadado.sql
rm -f scripts/rodar-tarefa.ps1
git checkout -- resources/pipeline.job.yml src/gold/05-dimensoes.sql \n                src/gold/06-fato-vendas.sql src/gold/07-marts.sql \n                src/ml/11-fila.sql 2>/dev/null || \
  echo "   (pipeline.job.yml não estava versionado — remova a tarefa gold_retorno_ligacao à mão)"

echo "→ redeploy: o job volta a 13 tarefas e o genie_direcao some..."
databricks bundle deploy --target dev --profile "$PROFILE"

echo
echo "→ verificação:"
echo "   genie spaces que sobraram:"
databricks genie list-spaces --profile "$PROFILE" 2>/dev/null | grep -E '"title"' || true
echo "   apps que sobraram:"
databricks apps list --profile "$PROFILE" 2>/dev/null | tail -n +2 || true
echo "   a fila da noite 3 continua de pé:"
sql "SELECT COUNT(*) AS contatos FROM $CATALOGO.gold.fila_semanal"

echo
echo "Pronto. O ambiente está como no fim da noite 3."
