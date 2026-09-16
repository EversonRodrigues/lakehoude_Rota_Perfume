#!/usr/bin/env bash
# Zera SÓ os retornos das ligações, e devolve o app ao estado de início de aula.
#
# É o que você roda entre um ensaio e outro: a fila dos 200 continua a mesma
# (ela é determinística — mesma seed, mesmo resultado), o modelo continua
# registrado, o Genie continua de pé. Some apenas o que foi clicado no app.
#
# Uso:  bash prd/99-limpar-retornos.sh <profile> [--apagar]
#       Sem --apagar ele só MOSTRA o que apagaria.
#
# Para apagar a noite 4 inteira (app, Genie e tabela), use o 99-limpar-aula-04.
set -euo pipefail

PROFILE="${1:?uso: bash prd/99-limpar-retornos.sh <profile> [--apagar]}"
CONFIRMA="${2:-}"
CATALOGO="${CATALOGO:-lakehouse_rotaperfume}"

sql() { echo "$1" | databricks experimental aitools tools query --profile "$PROFILE"; }

echo "→ o que está registrado hoje:"
sql "SELECT COUNT(*) AS retornos,
            COUNT(DISTINCT vendedor) AS vendedores,
            COUNT_IF(status = 'vendeu') AS vendeu
     FROM $CATALOGO.gold.retorno_ligacao"

if [ "$CONFIRMA" != "--apagar" ]; then
  echo
  echo "Simulação. Nada foi apagado."
  echo "Para apagar de verdade:  bash prd/99-limpar-retornos.sh $PROFILE --apagar"
  exit 0
fi

echo "→ apagando..."
sql "DELETE FROM $CATALOGO.gold.retorno_ligacao"

echo
echo "→ conferindo o estado de início de aula:"
sql "SELECT (SELECT COUNT(*) FROM $CATALOGO.gold.retorno_ligacao) AS retornos_agora,
            (SELECT COUNT(*) FROM $CATALOGO.gold.fila_semanal)    AS fila_intacta"

echo
echo "Pronto: retornos zerados, os 200 da fila intactos."
echo "No app, clique em Atualizar (aba Acompanhamento) ou recarregue a página —"
echo "a leitura é cacheada e a tela pode mostrar o número antigo por alguns segundos."
