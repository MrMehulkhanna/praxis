"""
Security regression tests for AIOS Local API authentication, Host/Origin validation, and CSRF protection.
"""
import pytest
from fastapi.testclient import TestClient
from app import app
from core import auth

@pytest.fixture
def client():
    return TestClient(app)

@pytest.fixture
def valid_token():
    return auth.token()

def test_public_root_accessible_without_token(client):
    res = client.get("/", headers={"Host": "127.0.0.1:8778"})
    assert res.status_code in (200, 404) or res.status_code < 400

def test_hostile_host_rejected(client, valid_token):
    # Host header pointing to external domain (e.g. DNS rebinding attack)
    res = client.get("/api/status", headers={
        "Host": "attacker.com",
        "Authorization": f"Bearer {valid_token}"
    })
    assert res.status_code == 421
    assert "loopback only" in res.json().get("detail", "")

def test_hostile_origin_rejected(client, valid_token):
    # Browser making cross-origin request from an untrusted site
    res = client.post("/api/settings/approve",
        headers={
            "Host": "127.0.0.1:8778",
            "Origin": "https://malicious-website.com",
            "Authorization": f"Bearer {valid_token}"
        },
        json={"run_key": "test"}
    )
    assert res.status_code == 403
    assert "Cross-origin requests from untrusted origins are blocked" in res.json().get("detail", "")

def test_missing_token_rejected(client):
    res = client.get("/api/status", headers={"Host": "127.0.0.1:8778"})
    assert res.status_code == 401
    assert "Missing or wrong token" in res.json().get("detail", "")

def test_invalid_token_rejected(client):
    res = client.get("/api/status", headers={
        "Host": "127.0.0.1:8778",
        "Authorization": "Bearer invalid_secret_token_12345"
    })
    assert res.status_code == 401
    assert "Missing or wrong token" in res.json().get("detail", "")

def test_valid_bearer_token_accepted(client, valid_token):
    res = client.get("/api/status", headers={
        "Host": "127.0.0.1:8778",
        "Authorization": f"Bearer {valid_token}"
    })
    assert res.status_code == 200

def test_valid_header_token_accepted(client, valid_token):
    res = client.get("/api/status", headers={
        "Host": "127.0.0.1:8778",
        "X-Praxis-Token": valid_token
    })
    assert res.status_code == 200

def test_oversized_payload_rejected(client, valid_token):
    # Content-Length claiming > 10MB
    res = client.post("/api/chat", headers={
        "Host": "127.0.0.1:8778",
        "Authorization": f"Bearer {valid_token}",
        "Content-Length": str(15 * 1024 * 1024)
    }, json={})
    assert res.status_code == 413
