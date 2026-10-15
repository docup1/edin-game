#!/usr/bin/env bash
# Прогон SQL-тестов против контейнера с PostgreSQL.
#   ./tests/run.sh          - поднять БД и прогнать тесты
#   ./tests/run.sh reset    - сначала снести volume (пересоздать схему/функции)
set -euo pipefail
cd "$(dirname "$0")/.."

DB_USER="${POSTGRES_USER:-edin}"
DB_NAME="${POSTGRES_DB:-edin}"

if [[ "${1:-}" == "reset" ]]; then
    echo ">> reset volume"
    docker compose down -v
fi

echo ">> docker compose up -d"
docker compose up -d

echo ">> waiting for postgres"
ready=0
for _ in $(seq 1 90); do
    if docker compose exec -T db psql -qtAX -U "$DB_USER" -d "$DB_NAME" -c 'SELECT 1' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done
if [[ "$ready" != "1" ]]; then
    echo "!! postgres не поднялся - смотри docker compose logs db"
    exit 1
fi

fail=0
for f in tests/*.sql; do
    [[ -e "$f" ]] || continue
    echo ">> $f"
    if ! docker compose exec -T db psql -v ON_ERROR_STOP=1 -q \
            -U "$DB_USER" -d "$DB_NAME" < "$f"; then
        echo "!! FAILED: $f"
        fail=1
    fi
done

if [[ "$fail" == "0" ]]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi
