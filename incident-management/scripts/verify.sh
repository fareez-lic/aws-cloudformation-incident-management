#!/usr/bin/env bash
set -euo pipefail

URL="${1:-http://127.0.0.1}"
URL="${URL%/}"

echo "[1/3] Checking Nginx frontend..."
curl --fail --show-error --silent "$URL/" >/dev/null

echo "[2/3] Checking backend health..."
curl --fail --show-error --silent http://127.0.0.1:5000/health \
  | grep -q '"status":"healthy"'

echo "[3/3] Checking incidents API..."
code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/incidents")
[[ "$code" == "200" || "$code" == "401" ]] || {
  echo "FAIL: incidents API returned HTTP $code"
  exit 1
}

echo "PASS: Frontend, backend health, and incidents API are available."
