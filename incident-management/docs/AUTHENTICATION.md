# Incident Management Authentication

The application now has a single administrator sign-in backed by server-side PostgreSQL sessions.

## What is protected

- `GET /api/incidents`
- `POST /api/incidents`
- `PATCH /api/incidents/:id/status`
- `DELETE /api/incidents/:id`

These endpoints require an active session. Login attempts are rate-limited, passwords are verified using Node.js scrypt, session cookies are HttpOnly and SameSite=Strict, session IDs are regenerated after login, and state-changing browser requests must include a same-origin Origin header.

## Set up the administrator

On a fresh Ubuntu 24.04 instance, install the app's required system dependencies first, then run:

```bash
cd ~/aws-cloudformation-incident-management/incident-management
bash scripts/setup-database.sh
```

The setup script creates a random administrator password if authentication settings do not already exist. Save the printed password in a password manager; the script intentionally does not print it again on subsequent runs. The settings are written to `backend/.env`, which must remain private and is excluded from Git.

Install the new Node.js dependencies and restart the backend service:

```bash
cd ~/aws-cloudformation-incident-management/incident-management/backend
npm install --no-audit --no-fund
npm run check
```

If a systemd service already exists, restart it using its actual service name. Do not copy the example password or commit the real `.env` file.

## HTTPS requirement

This is a learning implementation, not a production-ready identity system. Before exposing the app to the public internet:

1. Configure HTTPS at Nginx or a trusted load balancer.
2. Set `SESSION_COOKIE_SECURE=true` in the private `backend/.env` file.
3. Restart the backend and verify that login works only over HTTPS.
4. Restrict inbound network access and keep the backend and PostgreSQL bound to localhost.
5. Back up the session and incident database appropriately and monitor authentication failures.

The current implementation has one administrator account, no self-service password reset, and no per-user roles. Do not use it for real incident data or treat it as a complete enterprise authentication system.
