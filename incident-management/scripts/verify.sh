#!/usr/bin/env bash
set -euo pipefail
url="${1:-http://127.0.0.1:5173}"
url="${url%/}"
echo "Checking $url"
curl --fail --show-error --silent "$url/" >/dev/null
curl --fail --show-error --silent "$url/health" | grep -q '"status":"healthy"'
curl --fail --show-error --silent "$url/api/incidents" | grep -q '^\['
echo 'PASS: HTML, backend health and incidents API are available.'
