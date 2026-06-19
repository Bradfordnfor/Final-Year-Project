"""An unhandled server error must still come back as a JSON 500 carrying CORS
headers, so a browser client sees a real error instead of an opaque network
failure."""
from fastapi.testclient import TestClient
from app.main import app


def _boom():
    raise RuntimeError("intentional failure for the test")


# Register a throwaway route that always raises.
app.add_api_route("/_boom", _boom, methods=["GET"])


def test_unhandled_error_returns_500_with_cors_header():
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.get("/_boom", headers={"Origin": "http://localhost:5000"})
    assert resp.status_code == 500
    assert resp.json()["detail"] == "Internal server error"
    # the key property: CORS headers are present on the error response
    assert resp.headers.get("access-control-allow-origin") is not None
