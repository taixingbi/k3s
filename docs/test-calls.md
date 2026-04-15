# Test Calls

vLLM direct (`30080`):

```bash
curl http://192.168.86.173:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"where is jersey city"}],"max_tokens":50}'
```

gateway dev (`30180`):

```bash
curl http://192.168.86.173:30180/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"where is jersey city"}],"max_tokens":50}'
```

gateway prod (`30380`):

```bash
curl http://192.168.86.173:30380/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct","messages":[{"role":"user","content":"where is jersey city"}],"max_tokens":50}'
```
