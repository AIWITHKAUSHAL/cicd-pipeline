"""
The 'Automated Testing' requirement of the assignment.

Teaching point for the video: these tests run BEFORE any image is built.
If one fails the pipeline stops here, a broken image never reaches Docker
Hub, and therefore never reaches Kubernetes. That is the value of CI in
one sentence.
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_info_returns_version_color_and_pod():
    body = client.get("/api/info").json()
    assert set(body) == {"version", "color", "pod", "greeting"}


def test_add_happy_path():
    assert client.get("/api/add", params={"a": 2, "b": 3}).json()["sum"] == 5


def test_add_handles_negatives():
    assert client.get("/api/add", params={"a": -7, "b": 2}).json()["sum"] == -5


def test_add_rejects_huge_numbers():
    assert client.get("/api/add", params={"a": 99000000, "b": 1}).status_code == 400


def test_liveness_and_readiness_are_separate_endpoints():
    assert client.get("/health/live").json()["status"] == "alive"
    assert client.get("/health/ready").json()["status"] == "ready"


def test_home_page_renders():
    assert "version" in client.get("/").text


def test_responses_are_never_cached():
    """A cached response would show the old colour after a blue-green switch."""
    for path in ("/", "/api/info"):
        assert "no-store" in client.get(path).headers["cache-control"]
