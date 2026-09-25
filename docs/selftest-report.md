# AIOS self-test — 2026-09-21 21:44

**21 passed · 0 failed · 0 skipped**

| check | result | detail |
|---|---|---|
|| backend /api/status                | PASS   \| 140 memory objs|
|| /v1/models (OpenAI)                | PASS   \| |
|| /api/hardware                      | PASS   \| |
|| /api/providers                     | PASS   \| |
|| route: 'why is my gpu not detected' → sysadmin | PASS   \| |
|| route: 'compare rest vs grpc tradeof' → reasoning | PASS   \| |
|| route: 'hello there' → general   | PASS   \| |
|| route: 'write a binary search in rus' → code | PASS   \| |
|| route: 'fix this python traceback' → debug | PASS   \| |
|| local-qwen3-4b                     | PASS   \| 0.5 s · 20 tok · ~40.0 tok/s|
|| local-qwen3-8b                     | PASS   \| 8.1 s · 15 tok · ~1.9 tok/s|
|| local-coder-7b                     | PASS   \| 6.0 s · 6 tok · ~1.0 tok/s|
|| local-qwen3-vl-8b                  | PASS   \| 8.7 s · 13 tok · ~1.5 tok/s|
|| agent gathers evidence             | PASS   \| The available memory (RAM) is 12Gi, and the available disk s|
|| auto tier runs (volume)            | PASS   \| |
|| forbidden classifier (6 destructive cmds blocked) | PASS   \| |
|| confirm tier asks first            | PASS   \| |
|| vision reads an image              | PASS   \| yes|
|| voice allow-list (match/refuse/forward) | PASS   \| |
|| desk tracker                       | PASS   \| |
|| hardware: GPU=NVIDIA GeForce RTX 4050 Laptop GPU | PASS   \| |

## Measured model speed (this machine)
- **Qwen3 4B** (Daily): 9.3 tok/s · ~2.6 GB VRAM
- **Qwen3 8B** (Quality): 10.7 tok/s · ~4.2 GB VRAM
- **Qwen3-VL 8B** (Quality): 4.4 tok/s · ~4.5 GB VRAM
- **Qwen Coder 7B** (Code): 9.5 tok/s · ~4.6 GB VRAM
