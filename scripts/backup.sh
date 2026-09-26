#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/ufla-shop"
TIMESTAMP="$(date +%Y-%m-%d-%H%M)"
BACKUP_FILE="$BACKUP_DIR/loja-$TIMESTAMP.sql.gz"
TEMP_FILE="$BACKUP_FILE.tmp"

mkdir -p "$BACKUP_DIR"

trap 'rm -f "$TEMP_FILE"' EXIT
pg_dump loja | gzip > "$TEMP_FILE"
mv "$TEMP_FILE" "$BACKUP_FILE"

mapfile -t DUMPS_TO_DELETE < <(
	find "$BACKUP_DIR" -maxdepth 1 -type f -name 'loja-*.sql.gz' -printf '%T@ %p\n' |
		sort -rn |
		tail -n +8 |
		cut -d' ' -f2-
)

if [ "${#DUMPS_TO_DELETE[@]}" -gt 0 ]; then
	rm -f -- "${DUMPS_TO_DELETE[@]}"
fi

FILE_SIZE="$(stat -c '%s' "$BACKUP_FILE")"
logger -t backup "arquivo gerado: $BACKUP_FILE tamanho: ${FILE_SIZE} bytes"
