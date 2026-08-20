#!/usr/bin/env bash
# Counsel Engineering OS -- external deploy verification gate (POSIX parity)
# Provenance: ORIGINAL (Apache-2.0). Exit 0 = HTTP 200 AND sentinel present (if given).
# Usage: verify-deploy.sh <url> [sentinel] [retries] [delay-sec]
set -u
URL="${1:?usage: verify-deploy.sh <url> [sentinel] [retries] [delay]}"
SENTINEL="${2:-}"
RETRIES="${3:-3}"
DELAY="${4:-5}"

for attempt in $(seq 1 "$RETRIES"); do
  BODY_FILE="$(mktemp)"
  CODE="$(curl -s -o "$BODY_FILE" -w '%{http_code}' --max-time 30 "$URL" || echo 000)"
  if [ "$CODE" = "200" ]; then
    if [ -z "$SENTINEL" ] || grep -q -- "$SENTINEL" "$BODY_FILE"; then
      echo "VERIFY-DEPLOY OK: $URL -> 200${SENTINEL:+, sentinel found}"
      rm -f "$BODY_FILE"; exit 0
    fi
    echo "attempt $attempt: 200 but sentinel '$SENTINEL' NOT in response"
  else
    echo "attempt $attempt: HTTP $CODE"
  fi
  rm -f "$BODY_FILE"
  [ "$attempt" -lt "$RETRIES" ] && sleep "$DELAY"
done
echo "VERIFY-DEPLOY FAIL: $URL (after $RETRIES attempts)" >&2
exit 1
