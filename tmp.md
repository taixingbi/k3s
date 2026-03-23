curl http://192.168.86.173:31769/v1/models 

curl http://192.168.86.173:31769/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is new york city"}], "max_tokens": 50}'3



  sudo k3s kubectl get node gpu-node-2 -o go-template='{{index .status.allocatable "nvidia.com/gpu"}}{{"\n"}}'




tb@server-node-1:~$ sudo k3s kubectl get pods -n gpu-operator -o wide | grep device-plugin
nvidia-device-plugin-daemonset-ldpbs                              1/1     Running     0               4h46m   10.42.2.21   gpu-node-1      <none>           <none>
nvidia-device-plugin-daemonset-xbzmj                              1/1     Running     0               175m    10.42.3.24   gpu-node-2      <none>           <none>
tb@server-node-1:~$ 