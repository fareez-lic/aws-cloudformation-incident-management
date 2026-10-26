#!/usr/bin/env bash
# Quick Ubuntu EC2 diagnostic; run after deployment.
set -euo pipefail
for name in postgresql nginx incident-backend; do
  printf '%-20s' "$name"
  if sudo systemctl is-active --quiet "$name"; then echo 'active'; else echo 'not active'; fi
done
printf '\nListening sockets (expect public Nginx :80, localhost Node :5000 and PostgreSQL :5432):\n'
sudo ss -ltnp | grep -E '(:80 |:5000 |:5432 )' || true
printf '\nLocal HTTP checks:\n'
curl --fail --show-error --silent http://127.0.0.1/health || true
printf '\n'
