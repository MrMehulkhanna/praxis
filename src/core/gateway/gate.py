"""
Default-deny cost choke point.

A paid provider is UNREACHABLE without a spend token.
This is structural — not a flag someone forgets to set.

Modes:
  ZERO_COST    nothing leaves the machine (local only)          ← default
  LOCAL_ONLY   alias of ZERO_COST
  FREE_ONLINE  local + cloud models flagged free (no-cost tiers)
  APPROVAL     paid calls need a one-time approval each
  UNRESTRICTED paid calls allowed (keys required)
"""
import os
from core.store import db

class BudgetDenied(Exception):
    """Raised before any HTTP call is made to a paid provider."""

MODES = ("ZERO_COST", "LOCAL_ONLY", "FREE_ONLINE", "APPROVAL", "UNRESTRICTED")
_ENV_DEFAULT = os.environ.get("AIOS_BUDGET_MODE", "ZERO_COST")

_approved: set[str] = set()

def mode() -> str:
    m = db.kv_get("budget_mode", _ENV_DEFAULT)
    return m if m in MODES else "ZERO_COST"

def set_mode(m: str):
    if m not in MODES:
        raise ValueError(f"budget mode must be one of {MODES}")
    db.kv_set("budget_mode", m)

def approve_once(run_key: str):
    _approved.add(run_key)

def check(adapter, run_key: str, est_cost: float = 0.0, *, cloud: bool = False, free: bool = False):
    """Call BEFORE constructing any request that leaves the machine."""
    if not cloud:
        return   # local — always allowed
    m = mode()
    if m in ("ZERO_COST", "LOCAL_ONLY"):
        raise BudgetDenied(
            f"Budget mode is {m}: nothing is sent to cloud providers. "
            f"Switch to FREE_ONLINE (free tiers) or APPROVAL/UNRESTRICTED in Settings → AI.")
    if free:
        return   # free tier — allowed in FREE_ONLINE and above
    if m == "FREE_ONLINE":
        raise BudgetDenied(
            f"'{adapter.name}' model is paid (≈${est_cost:.4f}) and budget mode is FREE_ONLINE. Nothing was sent.")
    if m == "APPROVAL":
        if run_key in _approved:
            _approved.discard(run_key)
            return
        raise BudgetDenied(
            f"'{adapter.name}' needs explicit approval (≈${est_cost:.4f}). Approve in the UI or use `ai config approve`.")
    # UNRESTRICTED
