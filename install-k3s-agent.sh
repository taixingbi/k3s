#!/usr/bin/env bash
# Install k3s agent on gpu-node-1 (node). Joins the cluster at K3S_URL using K3S_TOKEN.
# Run as root or with sudo on the agent host. Set K3S_URL and K3S_TOKEN before running.

set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root or with sudo." >&2
  exit 1
fi

if [ -z "${K3S_URL}" ] || [ -z "${K3S_TOKEN}" ]; then
  echo "Usage: export K3S_URL=https://<server>:6443 K3S_TOKEN=<token>; $0" >&2
  echo "" >&2
  echo "K3S_URL   - k3s server URL (e.g. https://gpu-node-2:6443)" >&2
  echo "K3S_TOKEN - node token from the server (/var/lib/rancher/k3s/server/node-token)" >&2
  exit 1
fi

if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s-agent 2>/dev/null; then
  echo "k3s agent is already installed and running."
  exit 0
fi

curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN}" sh -s - agent

echo "k3s agent installed and joined the cluster."
