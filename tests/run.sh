#!/bin/sh
# Runs the backend checks with Docker (Linux): database access rules, then the app's data layer
# end to end against a local stand-in for Supabase. Used by the "Backend checks" workflow.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MIGRATION="$ROOT/supabase/migrations/20261125000000_brunello_schema.sql"
JWT_SECRET="local-test-secret-at-least-32-characters-long"
CHECK_SOURCES="$ROOT/tests/data-layer/Sources/DataLayerCheck"

# Behind a proxy (optional): pass it on, with its certificate, to the containers that download things.
NETWORK_ARGS="--network host -e NO_PROXY=127.0.0.1,localhost -e no_proxy=127.0.0.1,localhost"
if [ -n "${HTTPS_PROXY:-}" ]; then NETWORK_ARGS="$NETWORK_ARGS -e HTTPS_PROXY=$HTTPS_PROXY -e https_proxy=$HTTPS_PROXY"; fi
if [ -n "${SSL_CERT_FILE:-}" ]; then NETWORK_ARGS="$NETWORK_ARGS -v $SSL_CERT_FILE:/proxy-ca.crt:ro -e SSL_CERT_FILE=/proxy-ca.crt -e GIT_SSL_CAINFO=/proxy-ca.crt -e DENO_CERT=/proxy-ca.crt"; fi

cleanup() { docker rm -f brunello-test-db brunello-test-rest brunello-test-gateway >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Starts a clean Postgres with Supabase stand-ins and the real migration.
start_database() {
  docker rm -f brunello-test-db >/dev/null 2>&1 || true
  docker run -d --name brunello-test-db -e POSTGRES_PASSWORD=postgres postgres:17 >/dev/null
  for _ in $(seq 1 60); do
    if docker exec brunello-test-db psql -U postgres -c "select 1" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  sleep 2
  docker exec -i brunello-test-db psql -U postgres -v ON_ERROR_STOP=1 -q < "$ROOT/tests/stack/stubs.sql" 2>&1 | grep -v "wal_level\|HINT" || true
  docker exec -i brunello-test-db psql -U postgres -v ON_ERROR_STOP=1 -q < "$MIGRATION"
}

echo "== 1/2 Database access rules =="
cleanup
start_database
docker exec -i brunello-test-db psql -U postgres < "$ROOT/tests/database/access_rules.sql" > "$ROOT/tests/database/output.log" 2>&1 || true
if grep -E "FAIL|ERROR" "$ROOT/tests/database/output.log"; then echo "Database access rules: FAILED"; exit 1; fi
echo "Database access rules: $(grep -c "PASS" "$ROOT/tests/database/output.log") checks passed"

echo "== 2/2 App data layer, end to end =="
start_database
DATABASE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' brunello-test-db)
docker run -d --name brunello-test-rest --network host \
  -e PGRST_DB_URI="postgres://postgres:postgres@$DATABASE_IP:5432/postgres" -e PGRST_DB_SCHEMAS=public \
  -e PGRST_DB_ANON_ROLE=anon -e PGRST_JWT_SECRET="$JWT_SECRET" -e PGRST_SERVER_PORT=3000 \
  postgrest/postgrest:v13.0.7 >/dev/null
# shellcheck disable=SC2086
docker run -d --name brunello-test-gateway $NETWORK_ARGS -v "$ROOT:/repo:ro" \
  denoland/deno:2.5.6 run -A /repo/tests/stack/gateway.ts >/dev/null
for _ in $(seq 1 120); do
  if docker exec brunello-test-gateway deno eval "await fetch('http://127.0.0.1:54321/test/alerts')" >/dev/null 2>&1; then break; fi
  sleep 1
done

# Copy the app's real sources in, adapted for Linux: no OSLog, a local server, no Keychain.
rm -f "$CHECK_SOURCES"/App_*.swift
for file in "$ROOT"/Brunello/Models/*.swift "$ROOT/Brunello/Services/DiaryService.swift" "$ROOT/Brunello/App/AppConfig.swift"; do
  sed -e '/^import OSLog$/d' \
      -e 's#static let supabaseKey = ".*"#static let supabaseKey = "local-placeholder-key"#' \
      -e 's#static let supabaseURL = URL(string: "https://[^"]*")!#static let supabaseURL = URL(string: "http://127.0.0.1:54321")!#' \
      -e 's#auth: .init(emitLocalSessionAsInitialSession: true)#auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true)#' \
      "$file" > "$CHECK_SOURCES/App_$(basename "$file")"
done

# shellcheck disable=SC2086
docker run --rm $NETWORK_ARGS -v "$ROOT/tests/data-layer:/work" -w /work swift:6.1 \
  sh -c "swift build 2>&1 | grep -E 'error|Build complete' ; swift run --skip-build DataLayerCheck 2>&1 | grep -E 'PASS|FAIL|Fatal|ALL'" | tee "$ROOT/tests/data-layer/output.log"
grep -q "DATA LAYER CHECKS PASSED" "$ROOT/tests/data-layer/output.log"
echo "Backend checks: all passed"
