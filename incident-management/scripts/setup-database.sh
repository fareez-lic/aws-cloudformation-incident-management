#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux ]] || { echo 'This script requires Ubuntu Linux.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == '24.04' ]] || { echo 'Use Ubuntu 24.04 LTS.' >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Run as ubuntu user (with sudo), not root.' >&2; exit 1; }
command -v psql >/dev/null || { echo 'psql not found; run the OS installer first.' >&2; exit 1; }
command -v openssl >/dev/null || { echo 'openssl not found.' >&2; exit 1; }
DB_FILE="$(pwd)/backend/.env"
DB_NAME='incidentdb'
DB_USER='incident_user'
if [[ -e "$DB_FILE" ]]; then
  echo 'Existing backend/.env found; preserving its configured credentials.'
  # shellcheck disable=SC1090
  source "$DB_FILE"
  [[ "$DB_NAME" == incidentdb && "$DB_USER" == incident_user ]] || { echo 'This teaching installer expects the fixed incidentdb / incident_user names.' >&2; exit 1; }
  [[ -n "${DB_PASSWORD:-}" ]] || { echo 'Set DB_PASSWORD in backend/.env.' >&2; exit 1; }
else
  umask 077
  DB_PASSWORD="$(openssl rand -hex 24)"
  cat > "$DB_FILE" <<EOF
PORT=5000
HOST=127.0.0.1
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=incidentdb
DB_USER=incident_user
DB_PASSWORD=$DB_PASSWORD
EOF
  chmod 600 "$DB_FILE"
  echo 'Created backend/.env with a random password (file is ignored by Git).'
fi
# -v variables are quoted and safely escaped by psql format(%I, %L).
admin_psql=(sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d postgres)
"${admin_psql[@]}" -v "dbuser=$DB_USER" -v "dbpass=$DB_PASSWORD" -v "dbname=$DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'dbuser', :'dbpass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'dbuser') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'dbuser', :'dbpass') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'dbname', :'dbuser')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'dbname') \gexec
SQL
export PGPASSWORD="$DB_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -c 'SELECT current_user, current_database();'
unset PGPASSWORD
chmod 600 "$DB_FILE"
echo 'Database setup complete. The backend creates the incidents table on first startup.'
