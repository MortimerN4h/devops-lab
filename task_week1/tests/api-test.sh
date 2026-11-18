#!/usr/bin/env bash
# Black-box API test for the Notes API (see ../API.md).
# Works against any backend: BASE_URL=http://localhost:18080 ./api-test.sh

BASE_URL="${BASE_URL:-http://localhost:18080}"
PASS=0
FAIL=0

# request METHOD PATH [JSON_BODY]  ->  sets STATUS and BODY
request() {
  local method=$1 path=$2 data=$3 out
  if [ -n "$data" ]; then
    out=$(curl -s -w '\n%{http_code}' -X "$method" "$BASE_URL$path" \
      -H 'Content-Type: application/json' -d "$data")
  else
    out=$(curl -s -w '\n%{http_code}' -X "$method" "$BASE_URL$path")
  fi
  STATUS=$(echo "$out" | tail -n1)
  BODY=$(echo "$out" | sed '$d')
}

# check NAME EXPECTED_STATUS [TEXT_THAT_BODY_MUST_CONTAIN]
check() {
  local name=$1 want=$2 contains=$3
  if [ "$STATUS" = "$want" ] && { [ -z "$contains" ] || echo "$BODY" | grep -q "$contains"; }; then
    echo "PASS  $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $name (want $want${contains:+ containing $contains}, got $STATUS: $BODY)"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing $BASE_URL"

request GET /api/health
check "GET /api/health" 200 '"status":"ok"'

request GET /api/notes
check "GET /api/notes returns a list" 200 '^\['

request POST /api/notes '{"text":"api-test note","dueDate":"2026-12-31"}'
check "POST creates a note" 201 '"text":"api-test note"'
check "POST stores dueDate" 201 '"dueDate":"2026-12-31"'
ID=$(echo "$BODY" | sed -E 's/.*"id":"?([^",}]+)"?.*/\1/')

request POST /api/notes '{"text":"   "}'
check "POST blank text -> 400" 400 'VALIDATION_ERROR'

request POST /api/notes '{}'
check "POST missing text -> 400" 400 'VALIDATION_ERROR'

request POST /api/notes '{"text":"x","dueDate":"2026-02-30"}'
check "POST impossible dueDate -> 400" 400 'VALIDATION_ERROR'

request POST /api/notes '{bad json'
check "POST invalid JSON -> 400" 400 'INVALID_JSON'

request GET "/api/notes/$ID"
check "GET by id" 200 '"text":"api-test note"'

request GET /api/notes/does-not-exist
check "GET unknown id -> 404" 404 'NOT_FOUND'

request PUT "/api/notes/$ID" '{"text":"api-test updated","done":true}'
check "PUT updates a note" 200 '"done":true'
check "PUT without dueDate clears it" 200 '"dueDate":null'

request PUT "/api/notes/$ID" '{"text":""}'
check "PUT blank text -> 400" 400 'VALIDATION_ERROR'

request PUT /api/notes/does-not-exist '{"text":"x"}'
check "PUT unknown id -> 404" 404 'NOT_FOUND'

request DELETE "/api/notes/$ID"
check "DELETE removes a note" 204

request DELETE "/api/notes/$ID"
check "DELETE again -> 404" 404 'NOT_FOUND'

request GET "/api/notes/$ID"
check "GET after delete -> 404" 404 'NOT_FOUND'

request GET /api/nope
check "Unknown route -> 404 JSON" 404 'NOT_FOUND'

echo "----"
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
