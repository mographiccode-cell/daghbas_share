from fastapi.testclient import TestClient

from app.main import app


def test_root_works():
    client = TestClient(app)
    res = client.get("/")
    assert res.status_code == 200
    assert "running" in res.json()["message"].lower()


def test_health_works():
    client = TestClient(app)
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["status"] == "ok"
    assert "version" in body


def test_web_ui_works():
    client = TestClient(app)
    res = client.get("/ui")
    assert res.status_code == 200
    assert "text/html" in res.headers.get("content-type", "")
    html = res.text
    assert "Dark" in html
    assert "English" in html
    assert "لوحة تحكم الأدمن" in html
