# Deploy RAG Query (dev)

Service image: [taixingbi/layer-rag-query-v1](https://hub.docker.com/r/taixingbi/layer-rag-query-v1) — source: [layer-rag-query-v1](https://github.com/taixingbi/layer-rag-query-v1)

HTTP API: `POST /v1/rag/query` (JSON body; see upstream README). MCP clients use `http://<host>:30183/mcp` when using FastMCP HTTP transport. Required environment variables match upstream [`app/config.py`](https://github.com/taixingbi/layer-rag-query-v1/blob/main/app/config.py) and [`.env.example`](https://github.com/taixingbi/layer-rag-query-v1/blob/main/.env.example); the dev manifest sets cluster DNS for embedding, reranker, and inference services.

## Prerequisites

- Qdrant reachable at `QDRANT_URL` (manifest default: `http://192.168.86.179:6333` — adjust if yours differs).
- `layer-gateway-embedding`, `layer-gateway-reranker`, and `vllm-inference` already deployed so in-cluster URLs in `manifests/rag/layer-rag-query-dev.yaml` resolve.
- Port map: `docs/port.md` (`30183` dev).

## 1) Configure env (no `secretRef` by default)

Edit `manifests/rag/layer-rag-query-dev.yaml` for non-default Qdrant host, keys (`QDRANT_API_KEY`, `EMBEDDING_INTERNAL_KEY`), or model names. Optional Grafana Loki variables follow the same pattern as upstream `.env.example`.

## 2) Apply manifests

```bash
# optional: preload image on the node
sudo k3s ctr images pull docker.io/taixingbi/layer-rag-query-v1:latest

sudo k3s kubectl apply -f manifests/rag/layer-rag-query-dev.yaml
sudo k3s kubectl rollout restart deployment/layer-rag-query -n ai-dev
sudo k3s kubectl get pods,svc -n ai-dev -l app=layer-rag-query
sudo k3s kubectl get svc -A -o wide | grep 30183
sudo k3s kubectl get pods -n ai-dev -l app=layer-rag-query -o wide
```

## 3) Observability

After changing scrape rules, reload Prometheus:

```bash
sudo k3s kubectl apply -f manifests/observability/prometheus-grafana.yaml
sudo k3s kubectl rollout restart deployment/prometheus -n monitoring
```

Prometheus discovers Service `layer-rag-query` in `ai-dev` with label `workload=rag-query` (see `manifests/observability/prometheus-grafana.yaml`). Scrapes use `metrics_path: /metrics`; if the image does not expose that path yet, the target may show as down until the app exports Prometheus metrics.

NodePorts:

- dev: `30183`
