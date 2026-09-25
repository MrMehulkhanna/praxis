"""
Generic adapter for any OpenAI-compatible chat endpoint (Groq, OpenRouter,
Gemini's OpenAI shim, Mistral, Cerebras, GitHub Models, OpenAI itself…).

One class, configured from providers.json. Adding a provider = adding a
JSON entry + a key in aios.env. Removing one breaks nothing.
"""
import json, os, time
import httpx
from core.gateway.iface import Capability, Request, attach_images

class ProviderState:
    OK, UNCONFIGURED, DISABLED, AUTH, QUOTA, ERROR, OFFLINE = \
        "ok", "unconfigured", "disabled", "auth", "quota", "error", "offline"

class OpenAICompatAdapter:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.id = cfg["id"]
        self.name = cfg.get("name", self.id)
        self.base_url = cfg["base_url"].rstrip("/")
        self.key_env = cfg.get("api_key_env", "")
        self.models = cfg.get("models", [])
        self.enabled = bool(cfg.get("enabled", False))
        self.headers_extra = cfg.get("headers", {})
        # paid unless every listed model is flagged free
        self.paid = not all(m.get("free") for m in self.models) if self.models else True
        self.state = ProviderState.OK
        self.state_reason = ""
        self.cooldown_until = 0.0
        self.last_latency_ms: int | None = None
        self.failures = 0
        self.requests = 0

    @property
    def api_key(self) -> str:
        return os.environ.get(self.key_env, "") if self.key_env else ""

    def capabilities(self) -> Capability:
        return Capability(chat=True, tools=True)

    def status(self) -> str:
        if not self.enabled:
            return ProviderState.DISABLED
        if self.key_env and not self.api_key:
            return ProviderState.UNCONFIGURED
        if time.time() < self.cooldown_until:
            return self.state
        return ProviderState.OK

    def _mark(self, state: str, reason: str, cooldown_s: int):
        self.state, self.state_reason = state, reason[:200]
        self.cooldown_until = time.time() + cooldown_s
        self.failures += 1

    async def health(self) -> bool:
        return self.status() == ProviderState.OK

    def _headers(self) -> dict:
        h = {"Content-Type": "application/json", **self.headers_extra}
        if self.api_key:
            h["Authorization"] = f"Bearer {self.api_key}"
        return h

    async def run(self, req: Request):
        model = req.model.split("/", 1)[1] if "/" in req.model else req.model
        body = {
            "model": model, "stream": True,
            "max_tokens": req.max_tokens, "temperature": req.temperature,
            "messages": [{"role": "system", "content": req.system}, *attach_images(req.messages, req.images)],
        }
        self.requests += 1
        t0 = time.time()
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=10)) as c:
                async with c.stream("POST", f"{self.base_url}/chat/completions",
                                    headers=self._headers(), json=body) as resp:
                    if resp.status_code in (401, 403):
                        self._mark(ProviderState.AUTH, f"HTTP {resp.status_code}: key rejected", 3600)
                        raise RuntimeError(f"{self.name}: API key rejected (HTTP {resp.status_code})")
                    if resp.status_code == 429:
                        self._mark(ProviderState.QUOTA, "HTTP 429: rate/quota limit", 900)
                        raise RuntimeError(f"{self.name}: rate or quota limit hit — cooling down 15 min")
                    if resp.status_code >= 400:
                        text = (await resp.aread())[:300].decode(errors="replace")
                        self._mark(ProviderState.ERROR, f"HTTP {resp.status_code}: {text}", 120)
                        raise RuntimeError(f"{self.name}: HTTP {resp.status_code} {text}")
                    first = True
                    async for line in resp.aiter_lines():
                        if not line.startswith("data: "):
                            continue
                        payload = line[6:].strip()
                        if payload == "[DONE]":
                            break
                        try:
                            delta = json.loads(payload)["choices"][0].get("delta", {})
                        except Exception:
                            continue
                        tok = delta.get("content")
                        if tok:
                            if first:
                                self.last_latency_ms = int((time.time() - t0) * 1000); first = False
                            yield tok
        except httpx.ConnectError as e:
            self._mark(ProviderState.OFFLINE, str(e), 60)
            raise RuntimeError(f"{self.name}: unreachable ({e})")
        except httpx.TimeoutException:
            self._mark(ProviderState.ERROR, "timeout", 120)
            raise RuntimeError(f"{self.name}: timed out")
