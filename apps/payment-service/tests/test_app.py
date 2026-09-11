from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health():
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_ready():
    response = client.get("/ready")

    assert response.status_code == 200
    assert response.json()["status"] == "ready"


def test_create_payment():

    response = client.post(
        "/payments",
        json={
            "order_id": "ORD-1001",
            "customer_id": "CUS-2001",
            "amount": 149.99,
            "currency": "CAD"
        }
    )

    assert response.status_code == 201
    assert response.json()["status"] == "SUCCESS"
