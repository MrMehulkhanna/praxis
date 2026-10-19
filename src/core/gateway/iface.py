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
        path = pathlib.Path(p).expanduser()
        if not path.exists():
            continue
        mime = mimetypes.guess_type(str(path))[0] or "image/png"
        data = base64.b64encode(path.read_bytes()).decode()
        parts.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data}"}})
    if not parts:
        return messages
    out = list(messages)
    for i in range(len(out) - 1, -1, -1):
        if out[i]["role"] == "user":
            text = out[i]["content"] if isinstance(out[i]["content"], str) else ""
            out[i] = {"role": "user", "content": [{"type": "text", "text": text}, *parts]}
            break
    return out

@runtime_checkable
class Adapter(Protocol):
    id:   str
    paid: bool
    def capabilities(self) -> Capability: ...
    async def health(self) -> bool: ...
    async def run(self, req: Request) -> AsyncIterator[str]: ...
