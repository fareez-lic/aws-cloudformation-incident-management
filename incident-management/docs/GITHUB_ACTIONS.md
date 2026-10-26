# Part C — Automate manual Ubuntu EC2 deployment with GitHub Actions

## Learning objective

Students already deployed the application manually using `bash scripts/deploy-ubuntu.sh`. Now the **same deployment script** will run automatically after `git push` to `main`:

```text
Git push main → GitHub Actions checkout → install + validate → build UI
              → connect by SSH → rsync changed source → deploy-ubuntu.sh
              → systemd restart + Nginx reload → see updated website
```

This workflow deploys **application code** to an existing EC2 instance. It does **not** provision EC2; that can be a separate Terraform/CloudFormation homework assignment.

## Before you start

- Part B manual EC2 deployment must work first.
- GitHub repo contains `.github/workflows/deploy.yml`, but **never** commits `backend/.env` or SSH private keys.
- Default branch: `main`.
- Target AWS Ubuntu EC2 has outbound Internet access, Node, PostgreSQL, Nginx and app DB configured.
- The remote directory is `/home/ubuntu/incident-management-ubuntu-ec2` and remote user is `ubuntu` (the defaults of this example).
- Network path from GitHub runner to TCP **22** on EC2 must be available. **Important:** GitHub-hosted runner public IP ranges can change and whitelisting them all is discouraged. For a controlled class use a runner with a known fixed egress IP or a trusted self-hosted runner; allow SSH only from that egress IP. Do not leave TCP 22 open to the Internet. Production alternatives include AWS SSM/CodeDeploy or OIDC-authenticated deployments.
- The default Ubuntu EC2 `ubuntu` user is sudo-capable without a password; the deployment script requires sudo for installing Nginx config + systemd. This is **classroom only**. In a real system use a dedicated, least-privilege deploy account with narrowly scoped permissions.

## C1. Create a GitHub repository

1. GitHub → **New repository**, e.g., `bongodev-incident-native`. Private is a reasonable default.
2. In your local terminal, in this extracted Ubuntu-only project directory on your computer:

```bash
git init
git branch -M main
git add .
git status                   # Confirm backend/.env is NOT in staging
git commit -m 'Initial native incident management lab'
git remote add origin git@github.com:YOUR_USER/bongodev-incident-native.git
git push -u origin main
```

If using HTTPS, change the origin URL to `https://github.com/YOUR_USER/bongodev-incident-native.git` and authenticate appropriately. Never put passwords/tokens directly in a remote URL.

## C2. Create a dedicated SSH deployment key

On **your own computer** (Mac/Linux/Windows with OpenSSH):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/bongodev_incident_deploy -C 'github-actions-incident-deploy'
```

For unattended Actions authentication, you can create a key without a passphrase **only for this disposable classroom account** and store the private key in GitHub Actions secrets. On a production system prefer short-lived credentials and a managed deployment mechanism.

Install the **public** half on EC2 (connect with the original EC2 `.pem` key):

```bash
ssh -i ~/Downloads/bongodev.pem ubuntu@EC2_PUBLIC_IP
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Copy the exact single-line contents of the local public-key file
# ~/.ssh/bongodev_incident_deploy.pub into this file:
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

You can display the local public key with:

```bash
cat ~/.ssh/bongodev_incident_deploy.pub
```

Test your new key from your own computer:

```bash
ssh -i ~/.ssh/bongodev_incident_deploy ubuntu@EC2_PUBLIC_IP 'whoami && hostname'
```

## C3. Pin and verify the EC2 SSH host key (no blind trust)

On **EC2**, print the Ed25519 SSH host key fingerprint:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

On **your own computer**, fetch the **public host key**:

```bash
ssh-keyscan -t ed25519 EC2_PUBLIC_IP > ec2-host-key.txt
ssh-keygen -lf ec2-host-key.txt
```

Check that the fingerprints **match exactly**. Never treat the output of `ssh-keyscan` as authenticated without this comparison. Add the *complete contents* of `ec2-host-key.txt` as the GitHub secret `EC2_SSH_KNOWN_HOSTS` (including host/IP and public key). The file itself is not secret but is handled as one here for simplicity. Do not commit private keys to Git. A changed public IP requires refreshing the host key mapping and `EC2_HOST`.

## C4. Configure GitHub Actions variables and secrets

GitHub repo → **Settings → Secrets and variables → Actions**.

**Repository variables** (Variables tab):

| Name | Value |
|---|---|
| `EC2_HOST` | `EC2_PUBLIC_IP` or a stable DNS name |
| `EC2_USER` | `ubuntu` |
| `EC2_APP_DIR` | `/home/ubuntu/incident-management-ubuntu-ec2` |

**Repository secrets** (Secrets tab):

| Name | Value |
|---|---|
| `EC2_SSH_PRIVATE_KEY` | Entire content of `~/.ssh/bongodev_incident_deploy`, including BEGIN/END lines |
| `EC2_SSH_KNOWN_HOSTS` | Verified Ed25519 line in `ec2-host-key.txt` |

Do **not** add `DB_PASSWORD` to GitHub. The EC2 `backend/.env` remains on the server during rsync and is excluded from git.

## C5. Check the EC2 security group from your runner

GitHub-hosted Actions uses changing outbound IPs. Unless the GitHub runner can reach TCP 22 on EC2, deployment will time out. **Never weaken the security group by opening SSH to `0.0.0.0/0` just to make the workflow pass.** Use one of:

- Runner with dedicated/static outbound IP and SG rule `/32` (best for this SSH exercise).
- Instructor-managed self-hosted runner with a trusted fixed outbound address (never register an untrusted/public student repository to such a runner).
- For a more advanced cloud deployment, replace SSH with AWS SSM using OIDC; that does not require inbound port 22 from Actions.

Use a *disposable* demo EC2 instance and remove its SSH rule after the homework.

## C6. Run your first CI/CD pipeline

The provided workflow (`.github/workflows/deploy.yml`) automatically runs on **push to main** or via **Actions → Deploy native incident app → Run workflow**.

Jobs:

- `build`: Node 24, npm dependency install, syntax checks and React production build.
- `deploy`: only runs if the `build` job passed **and** the configured EC2 vars/secrets exist. It copies code using rsync while excluding `.env`, `node_modules`, `.git`, and `dist`, then runs `scripts/deploy-ubuntu.sh` on EC2.

You can run CI alone before adding EC2 secrets: the deploy job is skipped safely.

## C7. Trigger an observable update

In `frontend/src/main.jsx` on your own computer, change:

```jsx
<h1>Incident Command Center</h1>
```

To:

```jsx
<h1>Incident Command Center — GitHub Actions Deployment</h1>
```

Then:

```bash
git add frontend/src/main.jsx
git commit -m 'Update dashboard heading through CI/CD'
git push origin main
```

GitHub → Actions → inspect run, watch deploy job. Refresh `http://EC2_PUBLIC_IP` with a hard reload. **The backend stays on port 5000**; Nginx continues to serve port 80.

For a second demo, modify only the README; Actions still deploy, showing why pipelines can later add path filters.

## C8. Diagnose a failed deployment

| Failure | What to check |
|---|---|
| `npm install` fails | Internet or npm registry; inspect build job |
| `Permission denied (publickey)` | Public key absent in EC2 `authorized_keys`, wrong user, malformed secret, SSH perms |
| `Host key verification failed` | Verify fingerprint; update `EC2_SSH_KNOWN_HOSTS`, host/IP |
| `Connection timed out` | Runner cannot access inbound TCP 22; fix network allowlist, not DB ports |
| `rsync: permission denied` | `EC2_APP_DIR` must be writable by the chosen EC2 user |
| `sudo: a terminal is required` | Non-interactive sudo unavailable; use instructor-prepared permissions/runner or managed deployment |
| App loads but API fails | EC2 backend logs, DB service and Nginx proxy settings |

Useful manual EC2 commands:

```bash
sudo journalctl -u incident-backend -n 80 --no-pager
sudo systemctl status incident-backend --no-pager
sudo nginx -t
curl -f http://127.0.0.1/health
```

## C9. Student homework submission

Provide repo URL, Actions run URL (successful deploy), screenshot of EC2 web app after `main.jsx` heading change, and 4–6 sentences explaining how Actions connects and updates the server. Remove GitHub secrets/deploy key and terminate EC2 after class.
