#!/usr/bin/env bash
# Installs NVIDIA GPU Operator on the existing k3s cluster (Helm-based).
#
# Intended to run on gpu-node-2 (the k3s server), but it will manage the cluster remotely.
# Requires: curl, sudo, and network access to GitHub + NVIDIA Helm chart repo.
#
# Usage:
#   cd /home/tb/Desktop/k3s
#   sudo -E ./install-nvidia-gpu-operator.sh
#
# Environment overrides:
#   GPU_OPERATOR_VERSION         Helm chart/operator version (default: v25.3.3)
#   GPU_OPERATOR_NAMESPACE       Namespace for operator (default: gpu-operator)
#   GPU_NODE_NAME               Node to check allocatable on (default: gpu-node-1)
#
# Notes:
# - Uses your pre-installed NVIDIA driver (driver.enabled=false).
# - Allows Operator to install/configure NVIDIA Container Toolkit (toolkit.enabled=true).

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (sudo) so helm/k3s kubeconfig access works." >&2
  exit 1
fi

CLUSTER_KUBECONFIG="${K3S_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

if [[ ! -f "${CLUSTER_KUBECONFIG}" ]]; then
  echo "k3s kubeconfig not found at ${CLUSTER_KUBECONFIG}" >&2
  echo "Expected default on k3s: /etc/rancher/k3s/k3s.yaml" >&2
  exit 1
fi

GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v25.3.3}"
GPU_OPERATOR_NAMESPACE="${GPU_OPERATOR_NAMESPACE:-gpu-operator}"
GPU_NODE_NAME="${GPU_NODE_NAME:-gpu-node-1}"

echo "Installing NVIDIA GPU Operator:"
echo "  chart/operator version: ${GPU_OPERATOR_VERSION}"
echo "  namespace: ${GPU_OPERATOR_NAMESPACE}"
echo "  node allocatable check: ${GPU_NODE_NAME}"
echo ""

if ! command -v helm >/dev/null 2>&1; then
  echo "Helm not found; installing Helm 3 (client-side) ..."
  tmp_get_helm="$(mktemp)"
  curl -fsSL -o "${tmp_get_helm}" https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod 700 "${tmp_get_helm}"
  "${tmp_get_helm}"
  rm -f "${tmp_get_helm}"
fi

echo "Helm version: $(helm version --short 2>/dev/null || helm version)"

echo "Adding NVIDIA Helm repo ..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "Ensuring namespace exists: ${GPU_OPERATOR_NAMESPACE}"
k3s kubectl create namespace "${GPU_OPERATOR_NAMESPACE}" >/dev/null 2>&1 || true

echo "Best-effort: labeling namespace for privileged pods (Pod Security Admission)"
kubectl_label_cmd=(k3s kubectl label --overwrite ns "${GPU_OPERATOR_NAMESPACE}" pod-security.kubernetes.io/enforce=privileged)
"${kubectl_label_cmd[@]}" >/dev/null 2>&1 || true

RELEASE_NAME="${GPU_OPERATOR_RELEASE_NAME:-nvidia-gpu-operator}"

echo "Installing/upgrading Helm release: ${RELEASE_NAME}"

HELM_BASE_ARGS=(
  --kubeconfig "${CLUSTER_KUBECONFIG}"
  -n "${GPU_OPERATOR_NAMESPACE}"
)
HELM_WAIT_ARGS=(
  --wait
  --timeout 10m0s
)

# `helm status` does not support `--wait` / `--timeout`, so keep install/upgrade flags separate.
if helm status "${RELEASE_NAME}" "${HELM_BASE_ARGS[@]}" >/dev/null 2>&1; then
  helm upgrade "${RELEASE_NAME}" nvidia/gpu-operator \
    "${HELM_BASE_ARGS[@]}" \
    "${HELM_WAIT_ARGS[@]}" \
    --version "${GPU_OPERATOR_VERSION}" \
    --set driver.enabled=false \
    --set toolkit.enabled=true
else
  helm install "${RELEASE_NAME}" nvidia/gpu-operator \
    "${HELM_BASE_ARGS[@]}" \
    "${HELM_WAIT_ARGS[@]}" \
    --version "${GPU_OPERATOR_VERSION}" \
    --set driver.enabled=false \
    --set toolkit.enabled=true
fi

echo ""
echo "Waiting for GPU resources to appear on node: ${GPU_NODE_NAME}"

alloc_value=""
for _ in $(seq 1 72); do
  # Use jsonpath with bracket syntax to handle the dot in "nvidia.com/gpu"
  alloc_value="$(
    k3s kubectl get node "${GPU_NODE_NAME}" \
      -o jsonpath='{.status.allocatable["nvidia.com/gpu"]}' 2>/dev/null || true
  )"
  if [[ "${alloc_value:-}" != "" && "${alloc_value:-}" != "0" ]]; then
    break
  fi
  sleep 5
done

echo ""
echo "Allocatable nvidia.com/gpu on ${GPU_NODE_NAME}: ${alloc_value:-<not-set>}"

echo ""
echo "Operator status (best-effort):"
k3s kubectl get pods -n "${GPU_OPERATOR_NAMESPACE}" -o wide 2>/dev/null || true

echo ""
echo "Next: apply the provided sample manifest to validate GPU scheduling:"
echo "  sudo -E k3s kubectl apply -f gpu-vectoradd-sample.yaml"

