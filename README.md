# k3s Server (server-node-1) and Agents (gpu-node-1, gpu-node-2)

Scripts and manifests for **server-node-1** as the k3s control plane and **gpu-node-1** / **gpu-node-2** as GPU workers.

| Host           | IP             | Role        |
|----------------|----------------|-------------|
| server-node-1  | 192.168.86.179 | k3s server  |
| gpu-node-1     | 192.168.86.173 | k3s agent   |
| gpu-node-2     | 192.168.86.176 | k3s agent   |

## Repository layout

| File | Purpose |
|------|---------|
| `install-k3s-server.sh` | Install k3s server; prints join URL and token |
| `install-k3s-agent.sh` | Join agent using `K3S_URL` + `K3S_TOKEN` |
| `install-nvidia-gpu-operator.sh` | Helm install GPU Operator (k3s containerd paths + device-plugin `runtimeClassName` patch) |
| `gpu-vectoradd-sample.yaml` | One-off pod: `nvidia-smi` to validate GPU scheduling |
| `inference-qwen25-7b.yaml` | Namespace `ai`, vLLM Qwen2.5-7B (2 replicas), Service NodePort **30080** |
| `tmp.md` | Local scratch notes (not part of install docs) |

## Prerequisites

- Root or sudo on all hosts
- Agents can reach server-node-1 on **6443**
- Use hostnames or IPs in `K3S_URL` depending on your DNS
- NVIDIA driver installed on each GPU node before GPU workloads (`nvidia-smi` on the host)

## Step 1: Install k3s server on server-node-1

```bash
sudo ./install-k3s-server.sh
```

When it finishes, it prints the **node token** and **join URL**. Use that token wherever this README shows `<K3S_TOKEN>`.

If k3s is already running, the script prints the token from 
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

## Step 2: Install k3s agent on gpu-node-1 and gpu-node-2

On **each** agent host (copy `install-k3s-agent.sh` first):

```bash
export K3S_URL=https://server-node-1.lan:6443
export K3S_TOKEN=K10337735b3793982cb8c66cb0fc2c95bbb8e9c16f8a0b1faa25a0330e7a0bf5a70::server:ff6b7aa08942eec8fb41be7d57f0dfe5
sudo -E ./install-k3s-agent.sh
```

If the server hostname is not resolvable:

```bash
export K3S_URL=https://192.168.86.179:6443
export K3S_TOKEN=K10337735b3793982cb8c66cb0fc2c95bbb8e9c16f8a0b1faa25a0330e7a0bf5a70::server:ff6b7aa08942eec8fb41be7d57f0dfe5
sudo -E ./install-k3s-agent.sh
```

## Verification

On **server-node-1**:

```bash
sudo k3s kubectl get nodes
```

Expect **server-node-1** (control-plane) and both GPU workers **Ready**.

### kubectl: run on the server

Use `sudo k3s kubectl …` on **server-node-1**. Agents do not run the API server; `kubectl` on a worker without `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` (copied from the server) fails with `localhost:8080` connection refused.

## Optional

- Pin k3s channel: `export INSTALL_K3S_CHANNEL=v1.34` (or similar) before `install-k3s-server.sh` / agent install via get.k3s.io
- Scripts are idempotent when k3s is already installed and running

## GPU support (NVIDIA, e.g. RTX 3090)

GPU workloads need the NVIDIA device plugin and container runtime integration on each GPU node.

### Install NVIDIA GPU Operator

On **server-node-1**:

```bash
cd /path/to/k3s
sudo -E ./install-nvidia-gpu-operator.sh
```

The script:

- Sets `driver.enabled=false`, `toolkit.enabled=true`
- Points the toolkit at k3s containerd: socket `/run/k3s/containerd/containerd.sock`, config `/var/lib/rancher/k3s/agent/etc/containerd/config.toml`
- Patches DaemonSet `nvidia-device-plugin-daemonset` with `runtimeClassName: nvidia` (needed on k3s so the plugin can see GPUs)

Environment overrides: `GPU_OPERATOR_VERSION`, `GPU_OPERATOR_NAMESPACE`, `GPU_NODE_NAMES`, `K3S_CONTAINERD_SOCKET`, `K3S_CONTAINERD_CONFIG` (see script header).

**Manual Helm** (same release name `nvidia-gpu-operator`; env order matches the script):

```bash
sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm upgrade --install nvidia-gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true \
  --set "toolkit.env[0].name=CONTAINERD_SOCKET" \
  --set "toolkit.env[0].value=/run/k3s/containerd/containerd.sock" \
  --set "toolkit.env[1].name=CONTAINERD_CONFIG" \
  --set "toolkit.env[1].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml"
```

Then apply the device-plugin patch (same as the install script):

```bash
sudo k3s kubectl patch daemonset nvidia-device-plugin-daemonset -n gpu-operator \
  --type=merge \
  -p='{"spec":{"template":{"spec":{"runtimeClassName":"nvidia"}}}}'
```

### Reset GPU operator pods on one node

If a node shows `nvidia.com/gpu` allocatable but workloads get `Available: 0` at admission time:

```bash
sudo k3s kubectl cordon gpu-node-2
for pod in $(sudo k3s kubectl get pods -n gpu-operator -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | awk -v n=gpu-node-2 '$2==n {print $1}'); do
  sudo k3s kubectl delete pod "$pod" -n gpu-operator --force --grace-period=0
done
sudo k3s kubectl uncordon gpu-node-2
```

On **gpu-node-2**: `sudo systemctl restart k3s-agent` if the toolkit just updated containerd config.

### Verify allocatable GPU

```bash
sudo k3s kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
sudo k3s kubectl get pods -n gpu-operator -o wide | grep device-plugin
```

### GPU smoke test

```bash
sudo k3s kubectl apply -f gpu-vectoradd-sample.yaml
sudo k3s kubectl get pods -A -o wide | grep -i vectoradd
sudo k3s kubectl logs cuda-vectoradd
sudo k3s kubectl delete pod cuda-vectoradd
```

## vLLM: Qwen2.5-7B-Instruct (`inference-qwen25-7b.yaml`)

Single manifest: namespace **`ai`**, Deployment **`inference-qwen25-7b`**, **2 replicas**, rolling strategy `maxSurge: 0` / `maxUnavailable: 1` (avoids a third pod when you only have two GPUs). Service **`inference-qwen25-7b`**, **NodePort 30080** → container port 8000.

Pod spec: `runtimeClassName: nvidia`, `dnsPolicy: Default`, optional pod anti-affinity across hosts, readiness probe on `/health` (long initial delay for model load), `HF_HUB_ENABLE_HF_TRANSFER=1`.

Apply on **server-node-1**:

```bash
sudo k3s kubectl apply -f inference-qwen25-7b.yaml
sudo k3s kubectl get pods -n ai -o wide -w
sudo k3s kubectl get svc -n ai
```

**Scale** (still use `maxSurge: 0` in the manifest):

```bash
sudo k3s kubectl scale deployment inference-qwen25-7b -n ai --replicas=1
sudo k3s kubectl scale deployment inference-qwen25-7b -n ai --replicas=2
```

### Call the API

Use a node IP where NodePort works (usually **GPU nodes**, not always the control plane):

```bash
# GPU-node-1
curl http://192.168.86.173:30080/v1/models
curl http://192.168.86.173:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is jersey city"}], "max_tokens": 50}'

curl http://192.168.86.176:30080/v1/models
curl http://192.168.86.176:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is jersey city"}], "max_tokens": 50}'

curl http://192.168.86.179:30080/v1/models
curl http://192.168.86.179:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is jersey city"}], "max_tokens": 50}'
```

Port **8000** is only inside the pod unless you use NodePort or `port-forward`:

```bash
sudo k3s kubectl port-forward -n ai svc/inference-qwen25-7b 8000:8000
```

### NodePort and the control plane

**server-node-1** may not accept NodePort traffic to its own IP even when iptables allows it. Prefer **192.168.86.173** / **192.168.86.176** for `curl`, or `port-forward` from the server.

## Troubleshooting

**`UnexpectedAdmissionError` / `Available: 0` for `nvidia.com/gpu`**

- Ensure device plugin DaemonSet has `runtimeClassName: nvidia` (install script or patch above).
- Restart the device plugin pod on that node; on the agent, `sudo systemctl restart k3s-agent` after toolkit changes.
- Remove stray GPU test pods in `default` (e.g. `cuda-vectoradd`, manual `gpu-probe*`) that still request a GPU:

```bash
sudo k3s kubectl get pods -A --field-selector spec.nodeName=gpu-node-2 -o wide
```

**Second replica Pending; scheduler: insufficient GPU**

- Rolling update deadlock: keep `maxSurge: 0` (already in `inference-qwen25-7b.yaml`).
- Unblock with: scale to 0 → wait for pods gone → scale back to 2.

**CUDA error 804 on one node**

- Align NVIDIA driver versions across GPU nodes with what the vLLM image expects (e.g. 590.x on both).

**`modprobe nvidia`: Key was rejected**

- Disable **Secure Boot** or use Ubuntu signed `linux-modules-nvidia-*` for your kernel.

**k3s-agent: `bind: address already in use` on 127.0.0.1:6444**

```bash
sudo lsof -i :6444
sudo kill -9 <PID>   # or: sudo pkill -9 k3s
sudo systemctl start k3s-agent
```

**Logs for inference pods**

```bash
sudo k3s kubectl logs -n ai -l app=inference-qwen25-7b --tail=100
sudo k3s kubectl describe pod -n ai -l app=inference-qwen25-7b
```

Typical issues: OOM / reduce `--gpu-memory-utilization`; Hugging Face DNS — `dnsPolicy: Default` is set; model download time — readiness probe allows long startup.
