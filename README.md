# k3s Server (gpu-node-2) and Node (gpu-node-1)

Scripts to run k3s with **gpu-node-2** as the server (control plane) and **gpu-node-1** as a node (agent).

## Prerequisites

- Root or sudo on both hosts
- Network connectivity from gpu-node-1 to gpu-node-2 (port 6443)
- If hostnames `gpu-node-2` and `gpu-node-1` are not resolvable, use IP addresses in `K3S_URL` and when verifying
- Optional: GPU drivers on the node if you need GPU workloads

## Step 1: Install k3s server on gpu-node-2

Copy `install-k3s-server.sh` to **gpu-node-2** and run it as root (or with sudo):

```bash
sudo ./install-k3s-server.sh
```

When it finishes, it will print the **node token** and the **join URL**. Save the token; you need it for the agent.

## Step 2: Install k3s agent on gpu-node-1

Copy `install-k3s-agent.sh` to **gpu-node-1**. Set the server URL and token from Step 1, then run:

```bash
export K3S_URL=https://gpu-node-2:6443
export K3S_TOKEN=K10068f3ec7343811686d772c8567796565dbc7fbb198761056b8a36feea0bac1d5::server:b23373d01da11c5b1f38b94552c58cd4
sudo -E ./install-k3s-agent.sh
```

If `gpu-node-2` is not resolvable from gpu-node-1, use the server’s IP:

```bash
export K3S_URL=https://192.168.86.176:6443
export K3S_TOKEN=K10068f3ec7343811686d772c8567796565dbc7fbb198761056b8a36feea0bac1d5::server:b23373d01da11c5b1f38b94552c58cd4
sudo -E ./install-k3s-agent.sh
```

## Verification

On **gpu-node-2** (the server), run:

```bash
sudo k3s kubectl get nodes
```

You should see both **gpu-node-2** (control-plane) and **gpu-node-1** (worker), and both in `Ready` once the agent has joined.

## Optional

- To pin the k3s version, set `INSTALL_K3S_CHANNEL` (e.g. `v1.28`) before running the install script.
- Scripts are idempotent: running them again skips install if k3s is already installed and running.

## GPU Support (NVIDIA 3090)

GPU workloads require the Kubernetes NVIDIA stack (device plugin and container runtime integration).

### Prerequisites

- `nvidia-smi` works on each GPU node (`gpu-node-1` and `gpu-node-2`)
- Your cluster is up and both nodes are `Ready` (see `Verification` above)

### Install NVIDIA GPU Operator

Run on **gpu-node-2**:

```bash
cd /home/tb/Desktop/k3s
sudo -E ./install-nvidia-gpu-operator.sh
```

This installs the NVIDIA GPU Operator via Helm and configures it to use your pre-installed driver:

- `driver.enabled=false`
- `toolkit.enabled=true`
- k3s containerd paths:
  - socket: `/run/k3s/containerd/containerd.sock`
  - config: `/var/lib/rancher/k3s/agent/etc/containerd/config.toml`

### Verify device plugin + GPU allocatable

On **gpu-node-2**, run:

```bash
sudo k3s kubectl get pods -n gpu-operator -o wide | grep -i nvidia || true
sudo k3s kubectl get node gpu-node-1 -o go-template='{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}'
sudo k3s kubectl get node gpu-node-2 -o go-template='{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}'
```

You want the allocatable value to be a number (for the 3090 it should typically be `1` unless you’re using MIG/time-slicing).

### Run a GPU test pod

Run the included sample (vector add) on **gpu-node-2**:

```bash
sudo k3s kubectl apply -f gpu-vectoradd-sample.yaml
sudo k3s kubectl get pods -A -o wide | grep -i vectoradd || true
```

If the GPU Operator is working, the pod will schedule on one of the GPU nodes and move to `Running` briefly (then it may exit depending on the sample behavior).

### vLLM (Qwen2.5-7B-Instruct on gpu-node-1)

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

Common causes: GPU not allocatable on `gpu-node-1`, image still pulling, or admission errors.

If pods show **`UnexpectedAdmissionError`**, the manifest is adjusted to avoid common Pod Security violations:

1. Do not set `runtimeClassName: nvidia` (GPU Operator already injects runtime handling)
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

### Expose the vLLM Deployment with a NodePort Service.

Run on your k3s server node:

# 1) Create NodePort service for vLLM deployment
```bash
sudo k3s kubectl expose deployment vllm-qwen25-7b \
  --name vllm-qwen25-7b-svc \
  --type NodePort \
  --port 8000 \
  --target-port 8000
```

# 2) Get the assigned node port
```bash
sudo k3s kubectl get svc vllm-qwen25-7b-svc -o wide
```

### vLLM (BAAI/bge-m3 on gpu-node-1, port 8001)

Manifest: `vllm-bge-m3.yaml` (Deployment name: `vllm-bge-m3`).

```bash
sudo k3s kubectl apply -f vllm-bge-m3.yaml
sudo k3s kubectl get pods -l app=vllm-bge-m3 -o wide -w
sudo k3s kubectl port-forward deployment/vllm-bge-m3 8001:8001
```

Model serve arguments in this manifest:

```bash
vllm serve BAAI/bge-m3 --host 0.0.0.0 --port 8001 --gpu-memory-utilization 0.1
```