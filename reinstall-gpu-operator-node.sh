#!/usr/bin/env bash
# Reinstalls NVIDIA GPU Operator components on a specific node (e.g. gpu-node-2).
#
# Fixes the case where the device plugin runs without the nvidia runtime and
# cannot see GPUs (reports "Available: 0" despite node allocatable showing 1).
#
# Run on server-node-1. The target node (default: gpu-node-2) will have its
# GPU operator pods deleted and the device plugin DaemonSet patched with
# runtimeClassName: nvidia so the plugin can access the GPU.
#
# Usage:
#   cd /path/to/k3s
#   sudo -E ./reinstall-gpu-operator-node.sh [NODE_NAME]
#
# Example:
#   sudo -E ./reinstall-gpu-operator-node.sh gpu-node-2
#
# Environment:
#   GPU_OPERATOR_NAMESPACE   Namespace (default: gpu-operator)
#   TARGET_NODE              Override node name (or pass as first arg)

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root (sudo) so k3s kubeconfig access works." >&2
  exit 1
fi

CLUSTER_KUBECONFIG="${K3S_KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
GPU_OPERATOR_NAMESPACE="${GPU_OPERATOR_NAMESPACE:-gpu-operator}"
TARGET_NODE="${1:-${TARGET_NODE:-gpu-node-2}}"

if [[ ! -f "${CLUSTER_KUBECONFIG}" ]]; then
  echo "k3s kubeconfig not found at ${CLUSTER_KUBECONFIG}" >&2
  exit 1
fi

echo "Reinstalling GPU operator components on node: ${TARGET_NODE}"
echo ""

# 1. Cordon the node (optional - avoids scheduling during reinstall)
echo "Cordoning ${TARGET_NODE} ..."
k3s kubectl cordon "${TARGET_NODE}" 2>/dev/null || true

# 2. Delete GPU operator pods on the target node
echo "Deleting GPU operator pods on ${TARGET_NODE} ..."
for pod in $(k3s kubectl get pods -n "${GPU_OPERATOR_NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | awk -v n="${TARGET_NODE}" '$2==n {print $1}'); do
  echo "  Deleting ${pod}"
  k3s kubectl delete pod "${pod}" -n "${GPU_OPERATOR_NAMESPACE}" --force --grace-period=0 2>/dev/null || true
done

# 3. Patch device plugin DaemonSet to use nvidia runtime (so it can see GPUs)
echo ""
echo "Patching device plugin DaemonSet with runtimeClassName: nvidia ..."
if k3s kubectl get daemonset nvidia-device-plugin-daemonset -n "${GPU_OPERATOR_NAMESPACE}" &>/dev/null; then
  k3s kubectl patch daemonset nvidia-device-plugin-daemonset -n "${GPU_OPERATOR_NAMESPACE}" \
    --type=merge \
    -p='{"spec":{"template":{"spec":{"runtimeClassName":"nvidia"}}}}' 2>/dev/null || \
  k3s kubectl patch daemonset nvidia-device-plugin-daemonset -n "${GPU_OPERATOR_NAMESPACE}" \
    --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/runtimeClassName","value":"nvidia"}]' 2>/dev/null || \
  echo "  (runtimeClassName may already be set; continuing)"
else
  echo "  DaemonSet nvidia-device-plugin-daemonset not found; skip patch"
fi

# 4. Uncordon the node
echo ""
echo "Uncordoning ${TARGET_NODE} ..."
k3s kubectl uncordon "${TARGET_NODE}" 2>/dev/null || true

# 5. Wait for device plugin pod to be ready
echo ""
echo "Waiting for device plugin pod on ${TARGET_NODE} (up to 2 min) ..."
for i in $(seq 1 24); do
  if k3s kubectl get pods -n "${GPU_OPERATOR_NAMESPACE}" -o wide 2>/dev/null | grep -q "${TARGET_NODE}.*device-plugin.*Running"; then
    echo "  Device plugin pod is Running"
    break
  fi
  sleep 5
done

echo ""
echo "Node ${TARGET_NODE} GPU operator reinstall complete."
echo ""
echo "On ${TARGET_NODE}, optionally restart k3s-agent to pick up toolkit config:"
echo "  sudo systemctl restart k3s-agent"
echo ""
echo "Then check allocatable and vLLM pods (from server-node-1):"
echo "  sudo k3s kubectl get node ${TARGET_NODE} -o go-template='{{index .status.allocatable \"nvidia.com/gpu\"}}{{\"\\n\"}}'"
echo "  sudo k3s kubectl get pods -l app=vllm-qwen25-7b -o wide"
