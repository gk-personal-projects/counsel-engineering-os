#!/usr/bin/env bash
# Counsel Engineering OS -- external instrumentation verification gate (POSIX parity)
# Provenance: ORIGINAL (Apache-2.0). See verify-instrumentation.ps1 for the contract.
# Usage: verify-instrumentation.sh <project_key> [posthog_host] [personal_api_key] [project_id] [query_host]
set -u
PROJECT_KEY="${1:?usage: verify-instrumentation.sh <project_key> [host] [personal_api_key] [project_id] [query_host]}"
HOST="${2:-https://us.i.posthog.com}"
PERSONAL_KEY="${3:-}"
PROJECT_ID="${4:-}"
QUERY_HOST="${5:-https://us.posthog.com}"
CANARY="counsel-canary-$(date +%Y%m%d-%H%M%S)-$$"

CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST "${HOST%/}/i/v0/e/" \
  -H 'Content-Type: application/json' \
  -d "{\"api_key\":\"$PROJECT_KEY\",\"event\":\"counsel_instrumentation_canary\",\"distinct_id\":\"$CANARY\",\"properties\":{\"source\":\"verify-instrumentation\"}}" || echo 000)"
if [ "$CODE" != "200" ]; then
  echo "VERIFY-INSTRUMENTATION FAIL: capture endpoint HTTP $CODE" >&2; exit 1
fi
echo "canary accepted by capture endpoint ($CANARY)"

if [ -z "$PERSONAL_KEY" ] || [ -z "$PROJECT_ID" ]; then
  echo "VERIFY-INSTRUMENTATION OK (capture-accepted only; pass personal key + project id to verify queryability)"
  exit 0
fi

for i in $(seq 1 10); do
  sleep 15
  COUNT="$(curl -s --max-time 30 -X POST "${QUERY_HOST%/}/api/projects/$PROJECT_ID/query/" \
    -H "Authorization: Bearer $PERSONAL_KEY" -H 'Content-Type: application/json' \
    -d "{\"query\":{\"kind\":\"HogQLQuery\",\"query\":\"select count() from events where event = 'counsel_instrumentation_canary' and distinct_id = '$CANARY'\"}}" \
    | sed -n 's/.*"results":\[\[\([0-9]*\).*/\1/p')"
  if [ -n "$COUNT" ] && [ "$COUNT" -ge 1 ] 2>/dev/null; then
    echo "VERIFY-INSTRUMENTATION OK: canary queryable after $((i * 15))s"; exit 0
  fi
  echo "poll $i: not yet queryable"
done
echo "VERIFY-INSTRUMENTATION FAIL: canary never became queryable" >&2
exit 1
