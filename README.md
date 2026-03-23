# k3s Server (server-node-1) and Agents (gpu-node-1, gpu-node-2)

Scripts to run k3s with **server-node-1** as the server (control plane) and **gpu-node-1** and **gpu-node-2** as agents (worker nodes).

## Prerequisites

- Root or sudo on all hosts
- Network connectivity from gpu-node-1 and gpu-node-2 to server-node-1 (port 6443)
- If hostnames `server-node-1`, `gpu-node-1`, and `gpu-node-2` are not resolvable, use IP addresses in `K3S_URL` and when verifying
- Optional: GPU drivers on the node if you need GPU workloads

## Step 1: Install k3s server on server-node-1

Copy `install-k3s-server.sh` to **server-node-1** and run it as root (or with sudo):

```bash
sudo ./install-k3s-server.sh
```

When it finishes, it will print the **node token** and the **join URL**. Save the token; you need it for the agents.
K10337735b3793982cb8c66cb0fc2c95bbb8e9c16f8a0b1faa25a0330e7a0bf5a70::server:ff6b7aa08942eec8fb41be7d57f0dfe5

## Step 2: Install k3s agent on gpu-node-1 and gpu-node-2

Copy `install-k3s-agent.sh` to both **gpu-node-1** and **gpu-node-2**. Run the following on **each** agent host.

**On gpu-node-1:**

```bash
export K3S_URL=https://server-node-1.lan:6443
export K3S_TOKEN=K10337735b3793982cb8c66cb0fc2c95bbb8e9c16f8a0b1faa25a0330e7a0bf5a70::server:ff6b7aa08942eec8fb41be7d57f0dfe5
sudo -E ./install-k3s-agent.sh
```

**On gpu-node-2:**

```bash
export K3S_URL=https://server-node-2.lan:6443
export K3S_TOKEN=K10337735b3793982cb8c66cb0fc2c95bbb8e9c16f8a0b1faa25a0330e7a0bf5a70::server:ff6b7aa08942eec8fb41be7d57f0dfe5
sudo -E ./install-k3s-agent.sh
```

If `server-node-1` is not resolvable from the agents, use the server’s IP:

```bash
export K3S_URL=https://<server-node-1-IP>:6443
export K3S_TOKEN=<token-from-step-1>
sudo -E ./install-k3s-agent.sh
```

## Verification

On **server-node-1** (the server), run:

```bash
sudo k3s kubectl get nodes
```

You should see **server-node-1** (control-plane) plus **gpu-node-1** and **gpu-node-2** (workers), all in `Ready` once the agents have joined.

## Optional

- To pin the k3s version, set `INSTALL_K3S_CHANNEL` (e.g. `v1.28`) before running the install script.
- Scripts are idempotent: running them again skips install if k3s is already installed and running.

## GPU Support (NVIDIA 3090)

GPU workloads require the Kubernetes NVIDIA stack (device plugin and container runtime integration).

### Prerequisites

- `nvidia-smi` works on each GPU node (`gpu-node-1` and `gpu-node-2`)
- Your cluster is up and all nodes are `Ready` (see `Verification` above)

### Install NVIDIA GPU Operator

Run on **server-node-1**:

```bash
cd /path/to/k3s
sudo -E ./install-nvidia-gpu-operator.sh
```

This installs the NVIDIA GPU Operator via Helm and configures it to use your pre-installed driver:

- `driver.enabled=false`
- `toolkit.enabled=true`
- k3s containerd paths:
  - socket: `/run/k3s/containerd/containerd.sock`
  - config: `/var/lib/rancher/k3s/agent/etc/containerd/config.toml`

### Verify device plugin + GPU allocatable

On **server-node-1**, run:

```bash
sudo k3s kubectl get pods -n gpu-operator -o wide | grep -i nvidia || true
sudo k3s kubectl get node gpu-node-1 -o go-template='{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}'
sudo k3s kubectl get node gpu-node-2 -o go-template='{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}'
```

You want the allocatable value to be a number (for the 3090 it should typically be `1` unless you’re using MIG/time-slicing).

### Run a GPU test pod

Run the included sample (vector add) on **server-node-1**:

```bash
sudo k3s kubectl apply -f gpu-vectoradd-sample.yaml
sudo k3s kubectl get pods -A -o wide | grep -i vectoradd || true
```

If the GPU Operator is working, the pod will schedule on one of the GPU nodes and move to `Running` briefly (then it may exit depending on the sample behavior).

### vLLM (Qwen2.5-7B-Instruct on GPU nodes)

Manifest: `vllm-qwen2.5-7b-instruct.yaml` (Deployment name is **`vllm-qwen25-7b`** — no dots, valid DNS labels).

```bash
sudo k3s kubectl apply -f vllm-qwen2.5-7b-instruct.yaml
# Wait until Running (image pull + model download can take many minutes)
sudo k3s kubectl get pods -l app=vllm-qwen25-7b -o wide -w
# Only then:
sudo k3s kubectl port-forward deployment/vllm-qwen25-7b 8000:8000
```

If `port-forward` says the pod is **Pending**, check events:

```bash
sudo k3s kubectl describe pod -l app=vllm-qwen25-7b
```

Common causes: GPU not allocatable on GPU nodes, image still pulling, or admission errors.

If pods show **`UnexpectedAdmissionError`**, the manifest is adjusted to avoid common Pod Security violations:

1. The manifest omits `runtimeClassName: nvidia` (GPU Operator injects runtime handling)
2. Avoid `hostIPC: true` (Pod Security often blocks it)

Re-apply after cleanup:

```bash
sudo k3s kubectl delete deployment vllm-qwen25-7b --ignore-not-found
sudo k3s kubectl delete pods -l app=vllm-qwen25-7b --force --grace-period=0 2>/dev/null || true
sudo k3s kubectl apply -f vllm-qwen2.5-7b-instruct.yaml
```

Remove an old deployment if you applied an earlier revision with a dotted name:

```bash
sudo k3s kubectl delete deployment vllm-qwen2.5-7b --ignore-not-found
```

### Expose the vLLM Deployment with a NodePort Service

Run on **server-node-1**:

```bash
# 1) Create NodePort service for vLLM deployment
sudo k3s kubectl expose deployment vllm-qwen25-7b \
  --name vllm-qwen25-7b-svc \
  --type NodePort \
  --port 8000 \
  --target-port 8000

# 2) Get the assigned node port
sudo k3s kubectl get svc vllm-qwen25-7b-svc -o wide
```