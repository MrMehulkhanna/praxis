"""
Local API authentication.

The backend listens on loopback only, but loopback is not a security
boundary: every process running as this user — an editor plugin, an npm
postinstall script, a browser extension — can reach it, and the API can
read the memory store and run shell commands. So every request carries a
shared token that lives in a 0600 file only this user can read.

Two checks, both cheap, both before anything else runs:

  1. Host header must name loopback. A page on the internet cannot read a
     cross-origin response (no CORS headers are sent), but DNS rebinding
     makes a remote name resolve to 127.0.0.1 so the browser believes it
     is same-origin. Rebinding cannot forge the Host header, so pinning it
     closes that door.
  2. Authorization: Bearer <token> (or X-Praxis-Token) must match.

The UI page itself is exempt — it is how you obtain the token, and check 1
is what keeps it from leaking to a rebound origin.
"""
import hmac, os, pathlib, secrets

_cached: str | None = None

def home() -> pathlib.Path:
    return pathlib.Path(os.environ.get("AIOS_HOME", pathlib.Path.home() / "aios"))

def token_file() -> pathlib.Path:
    return home() / "config" / "aios.token"

def token() -> str:
    """The shared token, created on first use. 0600, owner-only."""
    global _cached
    if _cached:
        return _cached
    env = os.environ.get("AIOS_TOKEN", "").strip()
    if env:
        _cached = env
        return _cached
    f = token_file()
    try:
        existing = f.read_text().strip()
        if existing:
            _cached = existing
            return _cached
    except OSError:
        pass
    f.parent.mkdir(parents=True, exist_ok=True)
    fresh = secrets.token_urlsafe(32)
    # 0600 from the moment it exists — never a window where it is world-readable
    fd = os.open(f, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(fresh + "\n")
    _cached = fresh
    return _cached

def verify(presented: str | None) -> bool:
    if not presented:
        return False
    return hmac.compare_digest(presented.strip(), token())

def presented(headers) -> str | None:
    """Pull the token out of a request's headers, Bearer or raw."""
    auth = headers.get("authorization") or ""
    if auth[:7].lower() == "bearer ":
        return auth[7:]
    return headers.get("x-praxis-token") or (auth or None)

def host_ok(host: str | None) -> bool:
    """Only loopback names. Port is ignored; the socket already pinned it."""
    if not host:
        return False
    h = host.strip().lower()
    if h.startswith("["):                      # [::1] or [::1]:8778
        name = h[1:].split("]", 1)[0]
    elif h.count(":") == 1:                    # 127.0.0.1:8778
        name = h.rsplit(":", 1)[0]
    else:                                      # bare name, or a raw IPv6
        name = h
    allowed = {"127.0.0.1", "localhost", "::1", "localhost.localdomain"}
    extra = os.environ.get("AIOS_ALLOWED_HOSTS", "")
    allowed |= {h.strip().lower() for h in extra.split(",") if h.strip()}
    return name in allowed

def origin_ok(origin: str | None) -> bool:
    """Local clients (CLI, quickshell, curl) don't send Origin -> allowed.
    If an Origin header is sent by a browser, it must be loopback only."""
    if not origin:
        return True
    o = origin.strip().lower()
    allowed_prefixes = (
        "http://127.0.0.1", "https://127.0.0.1",
        "http://localhost", "https://localhost",
        "http://[::1]", "https://[::1]"
    )
    return any(o == p or o.startswith(p + ":") for p in allowed_prefixes)

