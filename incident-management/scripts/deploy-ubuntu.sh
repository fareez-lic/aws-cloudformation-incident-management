#!/usr/bin/env bash
# Re-runnable manual or CI/CD deployment; does not recreate or erase PostgreSQL data.
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Ubuntu 24.04 Linux required.' >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Run as the login user, not root.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == '24.04' ]] || { echo 'Ubuntu 24.04 required.' >&2; exit 1; }
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
[[ -f backend/.env ]] || { echo 'Missing backend/.env. First run bash scripts/setup-database.sh.' >&2; exit 1; }
command -v npm >/dev/null || { echo 'Node/npm missing. Run bash scripts/install-ubuntu.sh.' >&2; exit 1; }
command -v nginx >/dev/null || { echo 'Nginx missing.' >&2; exit 1; }
command -v rsync >/dev/null || { echo 'rsync missing; run bash scripts/install-ubuntu.sh.' >&2; exit 1; }
echo '[1/5] Installing dependencies ...'
for dir in backend frontend; do
  (cd "$dir" && if [[ -f package-lock.json ]]; then npm ci; else npm install; fi)
done
echo '[2/5] Building React frontend ...'
(cd frontend && npm run build)
echo '[3/5] Installing frontend files for Nginx ...'
sudo install -d -m 0755 /var/www/incident-management
sudo rsync -a --delete frontend/dist/ /var/www/incident-management/
sudo chown -R www-data:www-data /var/www/incident-management
sudo find /var/www/incident-management -type d -exec chmod 755 {} +
sudo find /var/www/incident-management -type f -exec chmod 644 {} +
echo '[4/5] Installing systemd backend service ...'
node_path="$(command -v node)"
# systemd quote for ExecStart and WorkingDirectory paths containing spaces.
[[ "$PROJECT_ROOT" != *' '* && "$node_path" != *' '* ]] || { echo 'Place the project in a directory without spaces on Ubuntu.' >&2; exit 1; }
sudo tee /etc/systemd/system/incident-backend.service >/dev/null <<EOF
[Unit]
Description=Incident Management Node.js API
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$(id -un)
WorkingDirectory=$PROJECT_ROOT/backend
Environment=NODE_ENV=production
EnvironmentFile=$PROJECT_ROOT/backend/.env
ExecStart=$node_path src/server.js
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
sudo chmod 644 /etc/systemd/system/incident-backend.service
sudo systemctl daemon-reload
sudo systemctl enable --now incident-backend
sudo systemctl restart incident-backend
echo '[5/5] Configuring Nginx reverse proxy ...'
sudo install -m 0644 deploy/nginx-incident-management.conf /etc/nginx/sites-available/incident-management
sudo ln -sfn /etc/nginx/sites-available/incident-management /etc/nginx/sites-enabled/incident-management
if [[ -e /etc/nginx/sites-enabled/default || -L /etc/nginx/sites-enabled/default ]]; then
  sudo rm -f /etc/nginx/sites-enabled/default
fi
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
for n in $(seq 1 20); do
  if curl --fail --silent http://127.0.0.1:5000/health >/dev/null; then break; fi
  sleep 2
done
echo
curl --fail --show-error --silent http://127.0.0.1:5000/health || { echo; echo 'Backend not healthy. Run: sudo journalctl -u incident-backend -n 100 --no-pager' >&2; exit 1; }
echo
echo 'Deployment complete. On EC2 browse http://YOUR_PUBLIC_IP/ (allow TCP 80).'
