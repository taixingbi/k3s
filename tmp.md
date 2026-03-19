sudo k3s kubectl scale deployment vllm-qwen25-7b --replicas=0 --ignore-not-found
sudo k3s kubectl scale deployment vllm-qwen2.5-7b --replicas=0 --ignore-not-found

sudo k3s kubectl delete deployment vllm-qwen25-7b --ignore-not-found
sudo k3s kubectl delete deployment vllm-qwen2.5-7b --ignore-not-found

sudo k3s kubectl delete rs -l app=vllm-qwen25-7b --ignore-not-found
sudo k3s kubectl delete rs -l app=vllm-qwen2.5-7b --ignore-not-found

sudo k3s kubectl delete pods -l app=vllm-qwen25-7b --force --grace-period=0 2>/dev/null || true
sudo k3s kubectl delete pods -l app=vllm-qwen2.5-7b --force --grace-period=0 2>/dev/null || true

sudo k3s kubectl delete pod cuda-vectoradd --ignore-not-found

sudo k3s kubectl describe node gpu-node-1 | sed -n '/Allocated resources:/,/Events:/p'






sudo k3s kubectl delete deployment vllm-qwen25-7b --ignore-not-found
sudo k3s kubectl apply -f vllm-qwen2.5-7b-instruct.yaml
sudo k3s kubectl get pods -o wide -w