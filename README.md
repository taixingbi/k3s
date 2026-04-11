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
| `inference-qwen25-7b.yaml` | Namespace `ai`, vLLM Qwen2.5-7B (2 replicas), ClusterIP **`vllm-inference:8000`**, NodePort **30080** |
| `layer-gateway-inference.yaml` | Namespace `ai`, [layer-gateway-inference-v1](https://github.com/taixingbi/layer-gateway-inference-v1) ([Docker Hub](https://hub.docker.com/r/taixingbi/layer-gateway-inference-v1)): request-level routing to vLLM on each GPU node; NodePort **30180**, in-cluster **`http://layer-gateway-inference.ai.svc.cluster.local:8010`** |
| `prometheus-grafana.yaml` | Namespace `monitoring`: Prometheus scrapes vLLM + DCGM, **remote_write** to Grafana Cloud (no in-cluster Grafana) |
| `alloy-loki-cloud.yaml` | Namespace `monitoring`: Grafana Alloy **DaemonSet** tails pod logs (per-node), adds K8s labels, parses CRI + JSON, **loki.write** to Grafana Cloud Loki (no in-cluster Loki) |
| `grafana-import/dashboard/*.json` | Grafana Cloud dashboard exports (Prometheus + **Loki** HTTP/log panels); see [`grafana-import/README.md`](grafana-import/README.md) |
| `grafana-import/alert/prometheus-alert-rules.yaml` | Prometheus-format rules for Grafana Cloud Alerting import |
| `tmp.md` / `tmp/` | Optional local scratch (gitignored; create yourself—never commit tokens or `glc_` keys) |

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

## Observability: Prometheus in k3s + Grafana Cloud (`prometheus-grafana.yaml`)

**Grafana** is **Grafana Cloud** only (dashboards / Explore in the browser). **Prometheus** runs in the cluster, scrapes workloads, and **remote_writes** to Grafana Cloud hosted Prometheus—same idea as [layer-observability-grafana](https://github.com/taixingbi/layer-observability-grafana) without a local Grafana container.

- **Inference (vLLM chat)**: job **`vllm-inference`**, label **`workload=inference`** → Endpoints for **`vllm-inference`** (`ai`, **8000**, `/metrics`) per pod.
- **GPU telemetry (DCGM)**: job **`dcgm-exporter`**, label **`workload=gpu-telemetry`** → DCGM Service in **`gpu-operator`** (`*dcgm-exporter`, **9400**). Requires [NVIDIA GPU Operator](#install-nvidia-gpu-operator).
- **Embedding (optional)**: jobs **`vllm-embedding-gpu-node-1|2`**, labels **`workload=embedding`**, **`service=embedding`**, **`model=BAAI/bge-m3`** → static **`192.168.86.173:8001`** / **`.176:8001`**. Requires embed vLLM on those hosts and pod→node IP reachability; edit `prometheus-config` if your LAN differs.

In **Grafana / Explore**, narrow to LLM paths with e.g. `{workload="inference"}`, `{workload="embedding"}`, or hardware with `{workload="gpu-telemetry"}`.

**Prometheus TSDB** is stored on PVC **`prometheus-data`** (`local-path`, **20Gi** on k3s). The Prometheus Deployment uses **`strategy: Recreate`** so only one pod mounts the **ReadWriteOnce** volume during upgrades (default RollingUpdate can leave a second pod in `CrashLoopBackOff`). If your cluster uses another `StorageClass`, edit the PVC in `prometheus-grafana.yaml` before apply. Migrating from an older manifest that used `emptyDir` will create a new volume (past in-memory metrics are not carried over).

**Grafana Cloud (hosted Prometheus)**: in-cluster Prometheus **remote_writes** to Grafana Cloud using **`remote_write`** in `prometheus-config` (push URL + instance **user** id in the ConfigMap, **API token** in Secret **`prometheus-grafana-cloud-remote-write`**, key **`api-key`**). Same idea as [layer-observability-grafana](https://github.com/taixingbi/layer-observability-grafana) Docker Compose + `.env`. In **Grafana Cloud → Explore**, use your hosted Prometheus datasource (e.g. `grafanacloud-*-prom`); allow a short delay after fixing the token before series appear.

1. **Put a real token in the Secret** (Grafana Cloud access policy with **`metrics:write`**). Do **not** commit real `glc_` tokens to git. If a token was ever pasted into chat, email, or a repo, **revoke it** in Grafana Cloud and create a new one.

   ```bash
   # From server-node-1 (example: token in env var — avoid putting it in shell history on shared machines)
   read -s GRAFANA_CLOUD_API_KEY && echo
   sudo k3s kubectl create secret generic prometheus-grafana-cloud-remote-write -n monitoring \
     --from-literal=api-key="$GRAFANA_CLOUD_API_KEY" \
     --dry-run=client -o yaml | sudo k3s kubectl apply -f -
   unset GRAFANA_CLOUD_API_KEY
   sudo k3s kubectl rollout restart deployment/prometheus -n monitoring
   ```

2. **If your push URL or instance id differ**, edit the `remote_write` block in ConfigMap **`prometheus-config`** (`prometheus-grafana.yaml`), re-apply, then reload or restart Prometheus (see below).

Apply on **server-node-1** (after GPU Operator and vLLM are up):

```bash
sudo k3s kubectl apply -f prometheus-grafana.yaml
sudo k3s kubectl get pods -n monitoring -o wide
sudo k3s kubectl get svc -n monitoring
```

If you previously applied an older manifest that included in-cluster Grafana, remove the leftover objects:

```bash
sudo k3s kubectl delete deployment grafana -n monitoring --ignore-not-found
sudo k3s kubectl delete svc grafana -n monitoring --ignore-not-found
sudo k3s kubectl delete secret grafana-admin -n monitoring --ignore-not-found
sudo k3s kubectl delete configmap grafana-datasources -n monitoring --ignore-not-found
```

**Prometheus** (optional UI for debugging): the Service is **ClusterIP** only — nothing listens on **`127.0.0.1:9090`** on the host until you forward a port. In one terminal:

```bash
sudo k3s kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Then open `http://127.0.0.1:9090` or reload config (see below).

**Reload Prometheus** after changing the Prometheus `ConfigMap` (`apply` the manifest or edit the config):

- **With port-forward running** (same host as `curl`):

```bash
sudo k3s kubectl apply -f prometheus-grafana.yaml
curl -X POST http://127.0.0.1:9090/-/reload
```

- **Without port-forward** (restart picks up the mounted config; brief scrape gap):

```bash
sudo k3s kubectl apply -f prometheus-grafana.yaml
sudo k3s kubectl rollout restart deployment/prometheus -n monitoring
```

Verify DCGM targets exist:

```bash
sudo k3s kubectl get svc -n gpu-operator | grep -i dcgm
```

In Prometheus (port-forward), **Status → Targets**: job `dcgm-exporter` should be **up** per GPU node.

In **Grafana Cloud**, import dashboards from **`grafana-import/dashboard/`** (see [`grafana-import/README.md`](grafana-import/README.md)) and alert rules from **`grafana-import/alert/prometheus-alert-rules.yaml`**; Prometheus originals live in [layer-observability-grafana](https://github.com/taixingbi/layer-observability-grafana).

## Logs: Grafana Alloy + Grafana Cloud Loki (`alloy-loki-cloud.yaml`)

[Grafana Alloy](https://grafana.com/docs/alloy/latest/) runs as a **DaemonSet** (`alloy-logs`): each replica tails **only pods on that node** (`spec.nodeName` filter). Streams carry labels **`namespace`**, **`pod`**, **`container`**, **`app`** (`app.kubernetes.io/name` then `app`), **`node`**, **`job`** (`namespace/container`), plus **`cluster=k3s`** from **`loki.write`**. A **`loki.process`** pipeline runs **`stage.cri`** (CRI log framing) and **`stage.json`** for optional fields such as **`status`**, **`duration_ms`**, **`path`**, **`method`**, **`level`**—edit ConfigMap **`alloy-loki-config`** if your JSON uses different keys. In Grafana, use **`| json`** in LogQL to query those fields. There is **no in-cluster Loki**; everything goes to **Grafana Cloud** via **`loki.write`**.

The manifest sets **`readOnlyRootFilesystem: true`**, **`emptyDir`** for **`/tmp`** and **`/var/lib/alloy/data`**, **`fsGroup: 473`**, and **`runAsUser`/`runAsGroup` `473`** (official Alloy image UID/GID) so the process can write state and temp files. **Liveness** uses **`/-/ready`**, not **`/-/healthy`**, so a bad Loki endpoint does not cause endless restarts (see [Alloy HTTP endpoints](https://grafana.com/docs/alloy/latest/reference/http/)).

### Configure Grafana Cloud Loki

1. In Grafana Cloud, create an access policy token with **`logs:write`**. From **Loki → Details**, copy the push **URL** (must end with **`/loki/api/v1/push`**) and the **User** (numeric id for basic auth).

2. Apply the manifest (placeholders in the bundled Secret are overwritten in the next step—do not put real secrets in git):

```bash
sudo k3s kubectl apply -f alloy-loki-cloud.yaml
```

3. Patch Secret **`alloy-grafana-cloud-loki`** in **`monitoring`**. Wrap the Grafana token in **single quotes** so the shell does not treat **`$`** inside **`glc_...`** as variable expansion (`"$glc_..."` is wrong and stores an empty or broken key).

```bash
sudo k3s kubectl create secret generic alloy-grafana-cloud-loki -n monitoring \
  --from-literal=loki-url='https://logs-prod-036.grafana.net/loki/api/v1/push' \
  --from-literal=loki-username='1529533' \
  --from-literal=api-key='glc_YOUR_TOKEN_HERE' \
  --dry-run=client -o yaml | sudo k3s kubectl apply -f -

sudo k3s kubectl rollout restart daemonset/alloy-logs -n monitoring
sudo k3s kubectl rollout status daemonset/alloy-logs -n monitoring
```

Optional: keep a local override file matching **`*-secret.local.yaml`** (gitignored) and `kubectl apply -f` it instead of embedding secrets in commands.

### Verify Alloy and the Secret

```bash
sudo k3s kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy-logs -o wide
sudo k3s kubectl describe secret alloy-grafana-cloud-loki -n monitoring
```

Expect **three** data keys with **non-zero** sizes. Decode **URL** and **username** only (avoid printing **`api-key`** in shared logs):

```bash
sudo k3s kubectl get secret alloy-grafana-cloud-loki -n monitoring -o jsonpath='{.data.loki-url}' | base64 -d; echo
sudo k3s kubectl get secret alloy-grafana-cloud-loki -n monitoring -o jsonpath='{.data.loki-username}' | base64 -d; echo
```

If Alloy misbehaves after a Secret change, **`rollout restart`** the DaemonSet (pods do not reload Secret mounts in place).

### Grafana Cloud: Explore and dashboards

In **Explore → Loki**, try `{cluster="k3s", namespace="ai"}`. Import **`grafana-import/dashboard/loki-logs-http.json`** for **4xx/5xx**, **p95/p99** on **`duration_ms`**, **top routes**, and **5xx by `path`** (panels assume JSON keys **`status`**, **`path`**, **`duration_ms`**; adjust queries or the Alloy **`stage.json`** block if your apps differ).

### Alloy troubleshooting (short)

| Symptom | Likely cause |
|---------|----------------|
| **`mkdir /var/lib/alloy/data: permission denied`** | Missing **`fsGroup`/`runAsUser` `473`** or no writable **`emptyDir`** for data/tmp—use the current **`alloy-loki-cloud.yaml`**. |
| **`401` / `403`** in Alloy logs | Wrong **Loki user id** or token; token missing **`logs:write`**; re-patch Secret with **single-quoted** `api-key`. |
| **`secret unchanged`** after `kubectl apply` | Same desired Secret as cluster; if you meant to change the token, use a new value and re-apply, then **restart** Alloy. |
| Pods **Running** but no lines in Loki | Narrow time range; confirm workloads emit logs; check Alloy logs for push errors. |

## vLLM: Qwen2.5-7B-Instruct (`inference-qwen25-7b.yaml`)

Single manifest: namespace **`ai`**, Deployment **`inference-qwen25-7b`**, **2 replicas**, rolling strategy `maxSurge: 0` / `maxUnavailable: 1` (avoids a third pod when you only have two GPUs). Services: **`vllm-inference`** ClusterIP **8000** (in-cluster / metrics); **`inference-qwen25-7b`** NodePort **30080** → container port 8000.

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

## Inference routing gateway (`layer-gateway-inference.yaml`)

[layer-gateway-inference-v1](https://github.com/taixingbi/layer-gateway-inference-v1) is published as [`taixingbi/layer-gateway-inference-v1`](https://hub.docker.com/r/taixingbi/layer-gateway-inference-v1). It proxies **`/v1/chat/completions`** to the two vLLM NodePort backends defined in the ConfigMap (defaults match this repo’s LAN: **192.168.86.173** and **192.168.86.176**, port **30080**). Cluster Service **`layer-gateway-inference`** exposes **8010**; NodePort **30180** matches the same firewall pattern as vLLM’s **30080**.

On **server-node-1** (optional pre-pull; kubelet can pull on first schedule):

```bash
# sudo k3s ctr images pull docker.io/taixingbi/layer-gateway-inference-v1:latest
sudo k3s kubectl apply -f layer-gateway-inference.yaml
sudo k3s kubectl get pods,svc -n ai -l app=layer-gateway-inference
```

If **Prometheus** is already installed from this repo, re-apply so it picks up the new **`layer-gateway-inference`** scrape job:

```bash
sudo k3s kubectl apply -f prometheus-grafana.yaml
```

### Test inference api

Use a node IP where NodePort works (usually **GPU nodes**, not always the control plane).

**If `curl` gets “Connection refused” on every node:** confirm the Service and endpoints exist, pods are **Ready**, then decide whether it is **host firewall** vs **no backends**:

```bash
sudo k3s kubectl get svc -n ai inference-qwen25-7b -o wide
sudo k3s kubectl get endpoints -n ai inference-qwen25-7b
sudo k3s kubectl get pods -n ai -o wide
```

On **gpu-node-1** (SSH to that host), try loopback — if this works but curls from **server-node-1** fail, open the NodePort on the workers (e.g. Ubuntu **ufw**: `sudo ufw allow 30080/tcp comment 'k3s vLLM NodePort'` on each node, then `sudo ufw reload`):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30080/docs
```

Reliable from **server-node-1** without NodePort routing: use **port-forward** (see end of this section).


[192.168.86.173:30080/docs](http://192.168.86.179:30080/docs)
```bash
# GPU-node-1
curl http://192.168.86.173:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is jersey city"}], "max_tokens": 50}'
```

[192.168.86.176:30080/docs](http://192.168.86.179:30080/docs)
```bash
# GPU-node-2
curl http://192.168.86.176:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is jersey city"}], "max_tokens": 50}'
```

[192.168.86.179:30080/docs](http://192.168.86.179:30080/docs)
```bash
# GPU-node-2
curl http://192.168.86.179:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages":
      [{"role": "user", "content": "where is jersey city"}],
      "max_tokens": 50}'
```





Port **8000** is only inside the pod unless you use NodePort or `port-forward`:

```bash
sudo k3s kubectl port-forward -n ai svc/inference-qwen25-7b 8000:8000
```
