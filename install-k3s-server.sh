#!/usr/bin/env bash
# Install k3s server on server-node-1 (control plane).
# Run as root or with sudo on the server host.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root or with sudo." >&2
  exit 1
fi

if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s 2>/dev/null; then
  echo "k3s server is already installed and running."
  echo ""
  echo "Node token (use on agents to join this cluster):"
  cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || true
  echo ""
  echo "Join URL: https://$(hostname -f 2>/dev/null || hostname):6443"
  exit 0
fi

curl -sfL https://get.k3s.io | sh -s - server

echo ""
echo "k3s server installed. Use the following to join nodes:"
echo ""
echo "  K3S_URL=https://$(hostname -f 2>/dev/null || hostname):6443"
echo "  K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)"
echo ""
echo "On the agent host, run:"
echo "  export K3S_URL=https://$(hostname -f 2>/dev/null || hostname):6443"
echo "  export K3S_TOKEN=<token-above>"
echo "  sudo -E ./install-k3s-agent.sh"
echo ""
