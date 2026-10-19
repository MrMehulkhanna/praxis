from dataclasses import dataclass, field
from typing import AsyncIterator, Protocol, runtime_checkable

@dataclass
class Request:
    system:      str
    messages:    list
    model:       str
    max_tokens:  int   = 1024
    temperature: float = 0.7
    fanout:      bool  = False   # ONLY the "Ask Multiple" button sets this True
    think:       bool  = False   # reasoning mode (Qwen3 <think>); slow, off by default
    images:      list  = field(default_factory=list)   # local file paths attached to the last user turn

@dataclass
class Capability:
    chat:     bool = True
    vision:   bool = False
    tools:    bool = False
    embed:    bool = False
    image_gen:bool = False

def attach_images(messages: list, images: list) -> list:
    """OpenAI-style content parts: text + base64 data URIs on the last user message."""
    if not images:
        return messages
    import base64, mimetypes, pathlib
    parts = []
    for p in images:
        if isinstance(p, dict):
            if "type" in p and p["type"] == "image_url":
                parts.append(p)
            elif "image_url" in p:
                parts.append({"type": "image_url", "image_url": p["image_url"] if isinstance(p["image_url"], dict) else {"url": p["image_url"]}})
            elif "url" in p:
                parts.append({"type": "image_url", "image_url": {"url": p["url"]}})
            continue
        if not isinstance(p, str) or not p.strip():
            continue
        p = p.strip()
        # Direct data URI or web URL
        if p.startswith("data:image/") or p.startswith("http://") or p.startswith("https://"):
            parts.append({"type": "image_url", "image_url": {"url": p}})
            continue
        # Local file path or file:// URL
        clean_path = p[7:] if p.startswith("file://") else p
        path = pathlib.Path(clean_path).expanduser()
        if not path.is_file():
            continue
        mime = mimetypes.guess_type(str(path))[0] or "image/png"
        try:
            data = base64.b64encode(path.read_bytes()).decode()
            parts.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data}"}})
        except Exception:
            continue
    if not parts:
        return messages
    out = list(messages)
    for i in range(len(out) - 1, -1, -1):
        if out[i]["role"] == "user":
            c = out[i]["content"]
            if isinstance(c, str):
                out[i] = {"role": "user", "content": [{"type": "text", "text": c}, *parts]}
            elif isinstance(c, list):
                out[i] = {"role": "user", "content": [*c, *parts]}
            break
    else:
        out.append({"role": "user", "content": [{"type": "text", "text": "Describe or analyze the attached image."}, *parts]})
    return out


@runtime_checkable
class Adapter(Protocol):
    id:   str
    paid: bool
    def capabilities(self) -> Capability: ...
    async def health(self) -> bool: ...
    async def run(self, req: Request) -> AsyncIterator[str]: ...
