# Deploy Gateway (dev/prod)

Gateway image: [taixingbi/layer-gateway-inference-v1](https://hub.docker.com/r/taixingbi/layer-gateway-inference-v1)

Apply dev and prod:

```bash
sudo k3s kubectl apply -f manifests/gateway/layer-gateway-inference-dev.yaml
sudo k3s kubectl apply -f manifests/gateway/layer-gateway-inference-prod.yaml
sudo k3s kubectl get pods,svc -n ai-dev -l app=layer-gateway-inference
sudo k3s kubectl get pods,svc -n ai-prod -l app=layer-gateway-inference
```

NodePorts:

- dev: `30180`
- prod: `30380`

If a NodePort is already taken:

```bash
sudo k3s kubectl get svc -A -o wide | grep 30180
sudo k3s kubectl get svc -A -o wide | grep 30380
```
