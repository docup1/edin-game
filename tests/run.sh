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
# На свежем volume entrypoint сначала поднимает временный сервер, прогоняет
# init-скрипты и только потом запускает настоящий. Одиночный "SELECT 1" может
# попасть в этот промежуток и получить "database system is shutting down",
# поэтому ждём, чтобы строка "ready to accept connections" в логах перестала
# появляться (со старта с нуля она мелькает дважды), и лишь затем пробуем вход.
ready=0
prev=-1
stable=0
for _ in $(seq 1 90); do
    cnt=$(docker compose logs db 2>/dev/null | grep -c 'database system is ready to accept connections' || true)
    if [[ "$cnt" -ge 1 && "$cnt" == "$prev" ]]; then
        stable=$((stable + 1))
    else
        stable=0
    fi
    prev=$cnt
    if [[ "$stable" -ge 2 ]] && \
       docker compose exec -T db psql -qtAX -U "$DB_USER" -d "$DB_NAME" -c 'SELECT 1' >/dev/null 2>&1; then
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
