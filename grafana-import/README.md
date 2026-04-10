# Grafana dashboards and Prometheus alert rules (import into Grafana Cloud)

Copied from [layer-observability-grafana](https://github.com/taixingbi/layer-observability-grafana) for convenience:

| Path | Upstream |
|------|----------|
| `dashboards/inference.json` | [dashboards/inference.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/inference.json) |
| `dashboards/embedding.json` | [dashboards/embedding.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/embedding.json) |
| `dashboards/gpu.json` | [dashboards/gpu.json](https://github.com/taixingbi/layer-observability-grafana/blob/main/dashboards/gpu.json) |
| `alert/prometheus-alert-rules.yaml` | [alert/prometheus-alert-rules.yaml](https://github.com/taixingbi/layer-observability-grafana/blob/main/alert/prometheus-alert-rules.yaml) |

## Dashboards

1. Grafana Cloud → **Dashboards** → **New** → **Import**.
2. Upload `inference.json`, `embedding.json`, or `gpu.json`.
3. Map **Prometheus** to your **hosted Prometheus / Mimir** datasource (same as Explore).
4. Save.

Dashboards use `__inputs` for the datasource UID; Grafana prompts on import.

## Alert rules

Per upstream file header: **Alerting** → **Alert rules** → **Import** → **Prometheus YAML file** (not Grafana provisioning YAML). Select your hosted Prometheus/Mimir datasource and a folder (e.g. **Layer Observability**).

**Note:** Queries assume metric labels such as `service="inference"`, `service="embedding"`, and `service="gpu"` where applicable. If your scrape config uses different labels (e.g. only `workload=...`), edit the imported rules or JSON panels to match your series.

To refresh from upstream:

```bash
curl -fsSL -o input/dashboards/inference.json \
  https://raw.githubusercontent.com/taixingbi/layer-observability-grafana/main/dashboards/inference.json
# repeat for other files as needed
```
