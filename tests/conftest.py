import pytest
from fastapi.testclient import TestClient

from app.main import create_app


@pytest.fixture
def client(tmp_path):
    """A fresh app backed by a throwaway SQLite file per test (no Postgres needed)."""
    app = create_app(database_url=f"sqlite:///{(tmp_path / 'test.db').as_posix()}")
    with TestClient(app) as c:
        yield c
