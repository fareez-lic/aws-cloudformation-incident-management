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
# Create authentication secrets once; preserve them on repeat runs.
if [[ -z "${ADMIN_USERNAME:-}" || -z "${ADMIN_PASSWORD_SALT:-}" || -z "${ADMIN_PASSWORD_HASH:-}" || -z "${SESSION_SECRET:-}" ]]; then
  NEW_ADMIN_PASSWORD="$(openssl rand -hex 16)"
  ADMIN_USERNAME='admin'
  ADMIN_PASSWORD_SALT="$(openssl rand -hex 16)"
  ADMIN_PASSWORD_HASH="$(node --input-type=module -e 'import { scryptSync } from "node:crypto"; console.log(scryptSync(process.argv[1], process.argv[2], 64).toString("hex"))' "$NEW_ADMIN_PASSWORD" "$ADMIN_PASSWORD_SALT")"
  SESSION_SECRET="$(openssl rand -hex 32)"
  cat >> "$DB_FILE" <<EOF
ADMIN_USERNAME=$ADMIN_USERNAME
ADMIN_PASSWORD_SALT=$ADMIN_PASSWORD_SALT
ADMIN_PASSWORD_HASH=$ADMIN_PASSWORD_HASH
SESSION_SECRET=$SESSION_SECRET
SESSION_COOKIE_SECURE=false
EOF
  chmod 600 "$DB_FILE"
  echo
  echo 'Created the application administrator. Save this password in a password manager:'
  printf 'Username: %s\nPassword: %s\n' "$ADMIN_USERNAME" "$NEW_ADMIN_PASSWORD"
  echo 'This password will not be displayed again. Set SESSION_COOKIE_SECURE=true after HTTPS is configured.'
else
  echo 'Existing application authentication credentials found; preserving them.'
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
