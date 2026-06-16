#!/usr/bin/env bash
# Deploy Indico with zh_Hant_TW translation for testing.
#
# Usage:
#   ./start.sh          – build image, start all services
#   ./start.sh stop     – stop and remove all containers
#   ./start.sh logs     – tail Indico logs
#   ./start.sh reload   – recompile PO→MO, rebuild app, restart (keeps DB data)
#   ./start.sh rebuild  – full teardown + rebuild + restart

set -euo pipefail

NETWORK=indico-test-net
PG=indico-postgres
REDIS=indico-redis
APP=indico-app
IMAGE=indico-zh-hant-tw:local
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$DIR/indico.conf"
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
        if [[ "$code" == "200" || "$code" == "302" ]]; then
            echo "   -> Ready!"
            return
        fi
        sleep 3
    done
    echo "   (may still be starting — check: ./start.sh logs)"
}

run_indico() {
    docker run --rm \
        --network "$NETWORK" \
        -v "$CONF:/opt/indico/etc/indico.conf:ro" \
        "$IMAGE" "$@"
}

compile_translations() {
    local po="$DIR/../indico/translations/zh_Hant_TW/LC_MESSAGES/messages-all.po"
    local mo="$DIR/../indico/translations/zh_Hant_TW/LC_MESSAGES/messages.mo"
    echo "==> Compiling messages-all.po → messages.mo ..."
    if ! command -v msgfmt &>/dev/null; then
        echo "ERROR: msgfmt not found. Install gettext: brew install gettext" >&2
        exit 1
    fi
    msgfmt --check -o "$mo" "$po"
    # Copy into docker build context
    cp "$po" "$DIR/messages-all.po"
    cp "$mo" "$DIR/messages.mo"
    echo "    OK ($(wc -l < "$po" | tr -d ' ') lines)"
}

build_image() {
    compile_translations
    echo "==> Building Indico image with zh_Hant_TW translation..."
    docker build -t "$IMAGE" "$DIR"
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

do_reload() {
    # Recompile PO→MO, rebuild image, restart only the app container.
    # PostgreSQL and Redis keep running so all data is preserved.
    compile_translations
    echo "==> Rebuilding app image..."
    docker build -t "$IMAGE" "$DIR"
    echo "==> Restarting app container..."
    docker rm -f "$APP" 2>/dev/null || true
    docker run -d \
        --name "$APP" \
        --network "$NETWORK" \
        -p "$PORT:8080" \
        -v "$CONF:/opt/indico/etc/indico.conf:ro" \
        "$IMAGE" \
        indico run -h 0.0.0.0 -p 8080 --reloader none --url "http://localhost:$PORT"
    wait_for_http
    echo "Reload complete. Open http://localhost:$PORT"
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

    echo "==> Installing required PostgreSQL extensions..."
    docker exec "$PG" psql -U indico -d indico \
        -c "CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS unaccent;" \
        -q

    echo "==> Initialising Indico database (first run only)..."
    run_indico indico db prepare 2>&1 \
        | grep -v "^Fontconfig\|UserWarning\|config =\|Logger" || true

    echo "==> Creating admin user..."
    docker run --rm \
        --network "$NETWORK" \
        -v "$CONF:/opt/indico/etc/indico.conf:ro" \
        "$IMAGE" \
        bash -c "
source /opt/indico/.venv/bin/activate
python3 - << 'PYEOF'
from indico.web.flask.app import make_app
app = make_app()
with app.app_context():
    from indico.modules.auth.models.identities import Identity
    from indico.modules.users import User
    from indico.modules.users.operations import create_user
    from indico.core.db import db
    EMAIL = 'admin@example.com'
    PASSWORD = 'Admin1234!'
    if User.query.filter(User.all_emails == EMAIL, ~User.is_deleted, ~User.is_pending).has_rows():
        print('Admin user already exists.')
    else:
        identity = Identity(provider='indico', identifier='admin', password=PASSWORD)
        user = create_user(EMAIL, {'first_name': 'Admin', 'last_name': 'User', 'affiliation': ''}, identity)
        user.is_admin = True
        db.session.add(user)
        db.session.commit()
        print(f'Created admin: {EMAIL} / {PASSWORD}')
PYEOF
" 2>&1 | grep -E "Created|already|Error" || true

    echo "==> Starting Indico web server..."
    docker run -d \
        --name "$APP" \
        --network "$NETWORK" \
        -p "$PORT:8080" \
        -v "$CONF:/opt/indico/etc/indico.conf:ro" \
        "$IMAGE" \
        indico run -h 0.0.0.0 -p 8080 --reloader none --url "http://localhost:$PORT"

    wait_for_http

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  Indico →  http://localhost:$PORT                     ║"
    echo "║                                                      ║"
    echo "║  Login:    admin@example.com                         ║"
    echo "║  Password: Admin1234!                                ║"
    echo "║                                                      ║"
    echo "║  Switch to Traditional Chinese (Taiwan):             ║"
    echo "║    Profile (top-right) → Preferences → Language      ║"
    echo "║    → 中文（臺灣）                                      ║"
    echo "║                                                      ║"
    echo "║  ./start.sh logs     – follow logs                   ║"
    echo "║  ./start.sh rebuild  – rebuild after PO changes      ║"
    echo "║  ./start.sh stop     – stop everything               ║"
    echo "╚══════════════════════════════════════════════════════╝"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

case "${1:-start}" in
    stop)    do_stop ;;
    logs)    do_logs ;;
    reload)  do_reload ;;
    rebuild) do_rebuild ;;
    start)   do_start ;;
    *)       echo "Usage: $0 [start|stop|logs|reload|rebuild]"; exit 1 ;;
esac
