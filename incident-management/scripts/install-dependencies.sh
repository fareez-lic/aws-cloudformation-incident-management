#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux ]] || { echo 'Ubuntu Linux required.' >&2; exit 1; }
command -v node >/dev/null || { echo 'Node missing; run the OS installer.' >&2; exit 1; }
command -v npm >/dev/null || { echo 'npm missing; run the OS installer.' >&2; exit 1; }
node -e "if(+process.versions.node.split('.')[0] < 22) process.exit(1)" || { echo 'Node.js >=22 is required.' >&2; exit 1; }
for dir in backend frontend; do
  echo "Installing $dir npm dependencies ..."
  (cd "$dir" && if [[ -f package-lock.json ]]; then npm ci; else npm install; fi)
done
