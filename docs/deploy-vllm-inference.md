# Deploy vLLM Inference

```bash
sudo k3s kubectl apply -f manifests/ai/inference-qwen25-7b.yaml
sudo k3s kubectl get pods,svc -n ai -o wide
```

Important ports from this manifest:

- `vllm-inference` ClusterIP service: `8000`
- NodePort service `inference-qwen25-7b`: `30080`
