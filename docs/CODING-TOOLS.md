# Using AIOS models in your editor

AIOS exposes an **OpenAI-compatible** endpoint, so any coding tool that lets you set a custom
base URL can use your local models — routed automatically and through the same cost gate.

```
Base URL:  http://127.0.0.1:8778/v1
API key:   anything (e.g. "local" — it is ignored; nothing leaves the machine in ZERO_COST)
Models:    auto · aios-code · aios-fast · aios-quality · aios-vision
           (or the raw ids: local-coder-7b, local-qwen3-4b, local-qwen3-8b, local-qwen3-vl-8b)
```

`auto` routes per request (code → Coder 7B, chat → 4B, etc). `aios-code` pins the coding model.
The endpoint does **not** touch your personal AIOS memory — the editor sends its own file context, so
completions stay clean. Every call still lands in the usage ledger (`ai usage`) and Activity feed.

---

## Antigravity / VS Code

Antigravity's built-in agent is Gemini-locked and can't be pointed at a local model. But Antigravity is a
VS Code fork, so install the **Continue** or **Cline** extension and point *it* at the endpoint above.
Continue config (`~/.continue/config.json`):

```json
{
  "models": [
    { "title": "AIOS auto",   "provider": "openai", "model": "auto",       "apiBase": "http://127.0.0.1:8778/v1", "apiKey": "local" },
    { "title": "AIOS coder",  "provider": "openai", "model": "aios-code",  "apiBase": "http://127.0.0.1:8778/v1", "apiKey": "local" }
  ],
  "tabAutocompleteModel": { "title": "AIOS fast", "provider": "openai", "model": "aios-fast", "apiBase": "http://127.0.0.1:8778/v1", "apiKey": "local" }
}
```

## Aider

```bash
export OPENAI_API_BASE=http://127.0.0.1:8778/v1
export OPENAI_API_KEY=local
aider --model openai/aios-code
```

## Zed

`settings.json` → `language_models.openai`:

```json
{ "language_models": { "openai": { "api_url": "http://127.0.0.1:8778/v1", "available_models": [
  { "name": "aios-code", "max_tokens": 6144 }, { "name": "auto", "max_tokens": 8192 } ] } } }
```

## Cline / Roo (VS Code)

Settings → API Provider: **OpenAI Compatible** · Base URL `http://127.0.0.1:8778/v1` · key `local` · model `aios-code`.

## Anything else / curl

```bash
curl http://127.0.0.1:8778/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"aios-code","messages":[{"role":"user","content":"refactor this loop"}]}'
```

Also answers `GET /v1/models` and Ollama's `GET /api/tags` for tools that probe those.

> Cloud coding models: enable a provider in `config/providers.json` + key in `aios.env`, leave `ZERO_COST`
> (`ai config budget FREE_ONLINE`), then use its id (e.g. `groq/llama-3.3-70b-versatile`). Same endpoint.

## Codex CLI (0.155+) — VERIFIED working with local models

Codex 0.155 uses the Responses API (AIOS implements `/v1/responses`). Config is already set up:

`~/.codex/config.toml` has an `[model_providers.aios]` block (base_url `http://127.0.0.1:8778/v1`,
`wire_api = "responses"`). Profiles live in `~/.codex/local.config.toml` (aios-code) and
`~/.codex/local-fast.config.toml` (aios-fast). Your default profile (gpt-5.6-terra) is untouched.

```bash
codex --profile local              # interactive, local coder model
codex --profile local-fast         # local fast model
codex exec --profile local "..."   # one-shot
```
