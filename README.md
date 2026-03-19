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

- `nvidia-smi` works on `gpu-node-1`
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

### Verify device plugin + GPU allocatable

On **gpu-node-2**, run:

```bash
sudo k3s kubectl get pods -n gpu-operator -o wide | grep -i nvidia || true
sudo k3s kubectl get node gpu-node-1 -o jsonpath='{.status.allocatable["nvidia.com/gpu"]}'
```

You want the allocatable value to be a number (for the 3090 it should typically be `1` unless you’re using MIG/time-slicing).

### Run a GPU test pod

Run the included sample (vector add) on **gpu-node-2**:

```bash
sudo k3s kubectl apply -f gpu-vectoradd-sample.yaml
sudo k3s kubectl get pods -A -o wide | grep -i vectoradd || true
```

If the GPU Operator is working, the pod will schedule on `gpu-node-1` and move to `Running` briefly (then it may exit depending on the sample behavior).
