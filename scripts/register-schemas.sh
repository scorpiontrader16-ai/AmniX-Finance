#!/usr/bin/env bash
# scripts/register-schemas.sh
# يسجل كل الـ .proto files في Schema Registry
#
# الاستخدام:
#   ./scripts/register-schemas.sh
#   SCHEMA_REGISTRY_URL=http://localhost:8081 PROTO_DIR=./proto ./scripts/register-schemas.sh

set -euo pipefail

REGISTRY_URL="${SCHEMA_REGISTRY_URL:-http://localhost:8081}"
PROTO_DIR="${PROTO_DIR:-./proto}"

echo "🔗 Schema Registry : $REGISTRY_URL"
echo "📁 Proto directory : $PROTO_DIR"
echo ""

# ─── تحقق من الـ dependencies ─────────────────────────────
if ! command -v curl &>/dev/null; then
  echo "❌ curl is required"
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "❌ jq is required — install: apt-get install jq  OR  brew install jq"
  exit 1
fi

# ─── انتظر الـ registry يكون ready ────────────────────────
wait_for_registry() {
  local attempts=0
  echo "⏳ Waiting for schema registry..."
  until curl -sf "$REGISTRY_URL/subjects" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 30 ]; then
      echo "❌ Schema registry not ready after 60s — is it running?"
      exit 1
    fi
    printf "   attempt %d/30...\r" "$attempts"
    sleep 2
  done
  echo "✅ Schema registry is ready"
}

# ─── سجل schema واحد ─────────────────────────────────────
register_schema() {
  local subject="$1"
  local schema_file="$2"

  local schema_content
  schema_content=$(cat "$schema_file")

  # اضبط BACKWARD compatibility (non-fatal لو فشل)
  curl -sf -X PUT \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    -d '{"compatibility":"BACKWARD"}' \
    "$REGISTRY_URL/config/$subject" >/dev/null 2>&1 || true

  # سجل الـ schema
  local payload
  payload=$(jq -n --arg s "$schema_content" '{"schema":$s,"schemaType":"PROTOBUF"}')

  local response http_code
  response=$(curl -sf -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    -d "$payload" \
    "$REGISTRY_URL/subjects/$subject/versions" 2>&1) || true

  # FIX: فصل الـ response body عن الـ http code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | head -n-1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    local schema_id
    schema_id=$(echo "$body" | jq -r '.id // "unknown"')
    echo "  ✅ $subject  (id: $schema_id)"
  else
    echo "  ❌ $subject failed — HTTP $http_code: $body"
    return 1
  fi
}

# ─── Main ─────────────────────────────────────────────────
wait_for_registry

if [ ! -d "$PROTO_DIR" ]; then
  echo "❌ Proto directory not found: $PROTO_DIR"
  exit 1
fi

# FIX: استخدام array بدل while-read subshell عشان الـ counter يشتغل صح
mapfile -t proto_files < <(find "$PROTO_DIR" -name "*.proto" | sort)

if [ "${#proto_files[@]}" -eq 0 ]; then
  echo "⚠️  No .proto files found in $PROTO_DIR"
  exit 0
fi

echo "📝 Registering ${#proto_files[@]} schema(s)..."
echo ""

FAILED=0
for proto_file in "${proto_files[@]}"; do
  subject=$(basename "$proto_file" .proto)
  if ! register_schema "$subject" "$proto_file"; then
    FAILED=$((FAILED + 1))
  fi
done

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "⚠️  Done with $FAILED failure(s)"
  exit 1
else
  echo "🎉 All ${#proto_files[@]} schema(s) registered successfully"
  echo ""
  echo "🔍 Verify: curl -s $REGISTRY_URL/subjects | jq ."
fi
