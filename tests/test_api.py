import os

import pytest
from fastapi.testclient import TestClient

from app.db import make_engine
from app.main import create_app


def test_health_returns_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_ready_when_database_reachable(client):
    r = client.get("/ready")
    assert r.status_code == 200
    assert r.json()["db"] == "up"


def test_ready_returns_503_when_database_down(client, tmp_path):
    # Point the app at a database file in a directory that does not exist -> connection fails.
    missing = (tmp_path / "missing-dir" / "db.sqlite").as_posix()
    client.app.state.engine = make_engine(f"sqlite:///{missing}")
    r = client.get("/ready")
    assert r.status_code == 503
    assert r.json()["db"] == "down"


def test_create_item(client):
    r = client.post("/items", json={"name": "rotate TLS cert"})
    assert r.status_code == 201
    body = r.json()
    assert body["id"] > 0
    assert body["status"] == "open"


def test_create_item_rejects_invalid_input(client):
    assert client.post("/items", json={"name": ""}).status_code == 422
    assert client.post("/items", json={"name": "x", "status": "bogus"}).status_code == 422


def test_list_items_returns_created_items(client):
    client.post("/items", json={"name": "a"})
    client.post("/items", json={"name": "b", "status": "closed"})
    names = [i["name"] for i in client.get("/items").json()]
    assert names == ["a", "b"]


def test_get_missing_item_returns_404(client):
    assert client.get("/items/9999").status_code == 404


def test_version_comes_from_environment(monkeypatch, tmp_path):
    monkeypatch.setenv("APP_VERSION", "9.9.9")
    app = create_app(database_url=f"sqlite:///{(tmp_path / 'v.db').as_posix()}")
    with TestClient(app) as c:
        assert c.get("/version").json() == {"version": "9.9.9"}


def test_request_id_is_echoed(client):
    r = client.get("/health", headers={"x-request-id": "abc123"})
    assert r.headers["x-request-id"] == "abc123"


def test_metrics_endpoint_exposed(client):
    client.get("/health")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text


@pytest.mark.skipif(
    os.getenv("RUN_INTENTIONAL_FAILURE") != "1",
    reason="Intentional failure: set RUN_INTENTIONAL_FAILURE=1 to prove CI blocks a bad build",
)
def test_intentional_failure(client):
    # Deliberately wrong expectation: /health returns 200, not 500.
    assert client.get("/health").status_code == 500
