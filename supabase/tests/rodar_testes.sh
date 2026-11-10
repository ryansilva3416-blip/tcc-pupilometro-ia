#!/usr/bin/env bash
# Sobe um Postgres temporário, aplica as migrations e roda os testes do CRM.
# Uso: bash supabase/tests/rodar_testes.sh   (precisa de PostgreSQL 15+ instalado)
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls -d /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
DADOS="$(mktemp -d)"
PORTA="${PORTA:-54329}"

"$BIN/initdb" -D "$DADOS" -U postgres -A trust >/dev/null
"$BIN/pg_ctl" -D "$DADOS" -o "-p $PORTA -k $DADOS" -l "$DADOS/log" start >/dev/null
trap '"$BIN/pg_ctl" -D "$DADOS" stop -m fast >/dev/null; rm -rf "$DADOS"' EXIT

PSQL=(psql -h "$DADOS" -p "$PORTA" -U postgres -d postgres -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" -f "$AQUI/stub_supabase.sql"
for m in "$AQUI"/../migrations/*.sql; do
  echo "Aplicando $(basename "$m")"
  "${PSQL[@]}" -f "$m"
done
"${PSQL[@]}" -f "$AQUI/teste_crm.sql"
