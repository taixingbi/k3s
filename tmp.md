curl http://192.168.86.173:31769/v1/models 

curl http://192.168.86.173:31769/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen2.5-7B-Instruct", "messages": [{"role": "user", "content": "where is new york city"}], "max_tokens": 50}'