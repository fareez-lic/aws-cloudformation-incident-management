#!/usr/bin/env bash
set -euo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Ubuntu Linux required.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == '24.04' ]] || { echo 'Ubuntu 24.04 required.' >&2; exit 1; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Run as sudo-capable user, not root.' >&2; exit 1; }
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
sudo install -d -m 0755 /usr/share/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/nodesource.gpg >/dev/null
sudo chmod 0644 /usr/share/keyrings/nodesource.gpg
arch="$(dpkg --print-architecture)"
case "$arch" in amd64|arm64) ;; *) echo "Unsupported CPU architecture: $arch" >&2; exit 1;; esac
printf 'Types: deb\nURIs: https://deb.nodesource.com/node_24.x\nSuites: nodistro\nComponents: main\nArchitectures: %s\nSigned-By: /usr/share/keyrings/nodesource.gpg\n' "$arch" | sudo tee /etc/apt/sources.list.d/nodesource.sources >/dev/null
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
node -e "if (process.versions.node.split('.')[0] !== '24') process.exit(1)" || { echo 'Expected Node.js 24.x but got a different version.' >&2; exit 1; }
node --version
npm --version
