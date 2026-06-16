#!/usr/bin/env bash
# Deploy Indico with zh_Hant_TW translation for testing.
#
# Usage:
#   ./start.sh          – build image, start all services, open browser
#   ./start.sh stop     – stop and remove all containers
#   ./start.sh logs     – tail Indico logs
#   ./start.sh rebuild  – rebuild image and restart (after translation changes)

set -euo pipefail

NETWORK=indico-test-net
PG=indico-postgres
REDIS=indico-redis
APP=indico-app
IMAGE=indico-zh-hant-tw:local
CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/indico.conf"
ADMIN_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create_admin.py"
PORT=8080

# ── helpers ──────────────────────────────────────────────────────────────────

wait_for_pg() {
    echo "   Waiting for PostgreSQL..."
    for i in $(seq 1 30); do
        if docker exec "$PG" pg_isready -U indico -q 2>/dev/null; then return; fi
        sleep 2
    done
    echo "ERROR: PostgreSQL did not start in time" >&2; exit 1
}

wait_for_http() {
    echo "   Waiting for Indico at http://localhost:$PORT ..."
    for i in $(seq 1 40); do
        code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" 2>/dev/null || true)
        if [[ "$code" == "200" || "$code" == "302" ]]; then return; fi
        sleep 3
    done
    echo "   (Indico may still be starting — check: ./start.sh logs)"
}

run_in_indico() {
    docker run --rm \
        --network "$NETWORK" \
        -v "$CONF:/etc/indico/indico.conf:ro" \
        "$IMAGE" "$@"
}

build_image() {
    echo "==> Building Indico image with zh_Hant_TW translation..."
    docker build -t "$IMAGE" "$(dirname "$CONF")"
}

# ── commands ─────────────────────────────────────────────────────────────────

do_stop() {
    echo "==> Stopping containers..."
    docker rm -f "$APP" "$PG" "$REDIS" 2>/dev/null || true
    docker network rm "$NETWORK" 2>/dev/null || true
    echo "    Done."
}

do_logs() {
    docker logs -f "$APP"
}

do_rebuild() {
    do_stop
    build_image
    do_start
}

do_start() {
    build_image

    echo "==> Creating Docker network..."
    docker network create "$NETWORK" 2>/dev/null || true

    echo "==> Starting PostgreSQL..."
    docker run -d --name "$PG" --network "$NETWORK" \
        -e POSTGRES_USER=indico \
        -e POSTGRES_PASSWORD=indico \
        -e POSTGRES_DB=indico \
        postgres:15-alpine

    echo "==> Starting Redis..."
    docker run -d --name "$REDIS" --network "$NETWORK" \
        redis:7-alpine

    wait_for_pg

    echo "==> Preparing database (first run)..."
    run_in_indico indico db prepare 2>&1 | grep -v "^$" || true

    echo "==> Creating admin user (if needed)..."
    docker run --rm \
        --network "$NETWORK" \
        -v "$CONF:/etc/indico/indico.conf:ro" \
        -v "$ADMIN_SCRIPT:/tmp/create_admin.py:ro" \
        "$IMAGE" \
        indico shell /tmp/create_admin.py 2>&1 | grep -E "Created|already" || true

    echo "==> Starting Indico web server..."
    docker run -d \
        --name "$APP" \
        --network "$NETWORK" \
        -p "$PORT:8080" \
        -v "$CONF:/etc/indico/indico.conf:ro" \
        "$IMAGE" \
        indico run -h 0.0.0.0 -p 8080

    wait_for_http

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  Indico is running at  http://localhost:$PORT          ║"
    echo "║                                                      ║"
    echo "║  Login:    admin@example.com                         ║"
    echo "║  Password: Admin1234!                                ║"
    echo "║                                                      ║"
    echo "║  Switch language:                                    ║"
    echo "║    Profile → Preferences → Language                  ║"
    echo "║    → 中文（臺灣）/ Chinese (Taiwan)                    ║"
    echo "║                                                      ║"
    echo "║  Commands:                                           ║"
    echo "║    ./start.sh logs     – follow Indico logs          ║"
    echo "║    ./start.sh rebuild  – rebuild after PO changes    ║"
    echo "║    ./start.sh stop     – stop everything             ║"
    echo "╚══════════════════════════════════════════════════════╝"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "${1:-start}" in
    stop)    do_stop ;;
    logs)    do_logs ;;
    rebuild) do_rebuild ;;
    start)   do_start ;;
    *)       echo "Usage: $0 [start|stop|logs|rebuild]"; exit 1 ;;
esac
