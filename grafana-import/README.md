# Grafana dashboards and Prometheus alert rules (import into Grafana Cloud)

Copied from [layer-observability-grafana](https://github.com/taixingbi/layer-observability-grafana) for convenience:

| Path | Upstream |
|------|----------|
| `dashboard/inference.json` | [dashboards/inference.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/inference.json) |
| `dashboard/embedding.json` | [dashboards/embedding.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/embedding.json) |
| `dashboard/gpu.json` | [dashboards/gpu.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/gpu.json) |
| `dashboard/loki-logs-http.json` | This repo: Loki / JSON log panels (4xx, 5xx, p95/p99, routes); use with `manifests/observability/alloy-loki-cloud.yaml` |
| `alert/prometheus-alert-rules.yaml` | [alert/prometheus-alert-rules.yaml](https://github.com/taixingbi/layer-observability-grafana/blob/main/alert/prometheus-alert-rules.yaml) |
| `alert/loki-gateway-log-level-alerts.yaml` | This repo: LogQL / Loki rules for gateway JSON `level` WARN and ERROR (`ai-dev` / `ai-prod`); use with `manifests/observability/alloy-loki-cloud.yaml` |

## Dashboards

1. Grafana Cloud → **Dashboards** → **New** → **Import**.
2. Upload `inference.json`, `embedding.json`, `gpu.json`, and (for Loki) `loki-logs-http.json`.
3. Map **Prometheus** or **Loki** to your Grafana Cloud datasource (same as Explore).
4. Save.

Dashboards use `__inputs` for the datasource UID; Grafana prompts on import.

## Alert rules

**Prometheus / Mimir** (`alert/prometheus-alert-rules.yaml`): per upstream file header, **Alerting** → **Alert rules** → **Import** → **Prometheus YAML file** (not Grafana provisioning YAML). Select your hosted Prometheus/Mimir datasource and a folder (e.g. **Layer Observability**).

**Loki / LogQL** (`alert/loki-gateway-log-level-alerts.yaml`): not imported via the Prometheus YAML flow above. Create **Grafana-managed** alert rules using your **Loki** datasource and the same LogQL as in that file (or sync via the Loki ruler API / `lokitool` if your stack supports it). Pick the same alert folder as your other rules.

**Note:** Prometheus rules assume metric labels such as `service="inference"`, `service="embedding"`, and `service="gpu"` where applicable. If your scrape config uses different labels (e.g. only `workload=...`), edit the imported rules or JSON panels to match your series.

To refresh from upstream:

```bash
curl -fsSL -o dashboard/inference.json \
  https://raw.githubusercontent.com/taixingbi/layer-observability-grafana/main/dashboards/inference.json
# repeat for other files as needed
```
