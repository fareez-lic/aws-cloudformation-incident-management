#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Ubuntu Linux required.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == '24.04' ]] || { echo 'Ubuntu 24.04 required.' >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Run as regular sudo-capable user, not root.' >&2; exit 1; }
cd "$(dirname "$0")/.."
echo '[1/4] Installing base utilities ...'
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl openssl ca-certificates gnupg unzip rsync
echo '[2/4] Installing Node.js 24 LTS ...'
bash scripts/install-nodejs-ubuntu.sh
echo '[3/4] Installing PostgreSQL ...'
bash scripts/install-postgresql-ubuntu.sh
echo '[4/4] Installing Nginx ...'
bash scripts/install-nginx-ubuntu.sh
echo
printf 'Done! Next run:\n  bash scripts/setup-database.sh\n  bash scripts/deploy-ubuntu.sh\n'
