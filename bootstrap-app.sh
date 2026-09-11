#!/bin/bash

set -e

APP_DIR="apps/payment-service"

echo "Creating NovaPay Payment Service..."

mkdir -p $APP_DIR/app
mkdir -p $APP_DIR/tests

cat > $APP_DIR/app/__init__.py <<'EOF'
EOF

cat > $APP_DIR/app/main.py <<'EOF'
import logging
import os
from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, Response, status
from pydantic import BaseModel, Field
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s"
)

logger = logging.getLogger("payment-service")


app = FastAPI(
    title="NovaPay Payment Service",
    description="Payment API used by the NovaPay AI DevOps Platform",
    version="1.0.0",
)


payment_counter = Counter(
    "novapay_payments_total",
    "Total number of payments processed"
)

refund_counter = Counter(
    "novapay_refunds_total",
    "Total number of refunds processed"
)


class PaymentRequest(BaseModel):
    order_id: str = Field(min_length=1)
    customer_id: str = Field(min_length=1)
    amount: float = Field(gt=0)
    currency: str = Field(default="CAD", min_length=3, max_length=3)


class Payment(BaseModel):
    payment_id: UUID
    order_id: str
    customer_id: str
    amount: float
    currency: str
    status: str
    created_at: datetime


payments: dict[UUID, Payment] = {}


@app.get("/")
def root():
    return {
        "service": "payment-service",
        "company": "NovaPay",
        "environment": os.getenv("ENVIRONMENT", "local"),
        "version": os.getenv("APP_VERSION", "1.0.0"),
    }


@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "payment-service"
    }


@app.get("/ready")
def ready():
    return {
        "status": "ready",
        "service": "payment-service"
    }


@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )


@app.post(
    "/payments",
    response_model=Payment,
    status_code=status.HTTP_201_CREATED,
)
def create_payment(request: PaymentRequest):

    payment_id = uuid4()

    payment = Payment(
        payment_id=payment_id,
        order_id=request.order_id,
        customer_id=request.customer_id,
        amount=request.amount,
        currency=request.currency.upper(),
        status="SUCCESS",
        created_at=datetime.now(timezone.utc),
    )

    payments[payment_id] = payment
    payment_counter.inc()

    logger.info(
        "payment_created payment_id=%s order_id=%s amount=%s",
        payment.payment_id,
        payment.order_id,
        payment.amount,
    )

    return payment


@app.get("/payments")
def list_payments():
    return list(payments.values())


@app.get("/payments/{payment_id}")
def get_payment(payment_id: UUID):

    payment = payments.get(payment_id)

    if not payment:
        raise HTTPException(
            status_code=404,
            detail="Payment not found"
        )

    return payment


@app.post("/payments/{payment_id}/refund")
def refund_payment(payment_id: UUID):

    payment = payments.get(payment_id)

    if not payment:
        raise HTTPException(
            status_code=404,
            detail="Payment not found"
        )

    if payment.status == "REFUNDED":
        raise HTTPException(
            status_code=409,
            detail="Payment already refunded"
        )

    payment.status = "REFUNDED"

    refund_counter.inc()

    logger.info(
        "payment_refunded payment_id=%s",
        payment_id
    )

    return payment
EOF


cat > $APP_DIR/requirements.txt <<'EOF'
fastapi==0.116.1
uvicorn[standard]==0.35.0
prometheus-client==0.22.1
pytest==8.4.2
httpx==0.28.1
EOF


cat > $APP_DIR/tests/test_app.py <<'EOF'
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
EOF


cat > $APP_DIR/Dockerfile <<'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

RUN useradd -m novapay

USER novapay

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF


cat > $APP_DIR/.dockerignore <<'EOF'
venv
.venv
__pycache__
.pytest_cache
*.pyc
.git
EOF


cat > $APP_DIR/.env.example <<'EOF'
ENVIRONMENT=local
APP_VERSION=1.0.0
LOG_LEVEL=INFO
EOF


echo ""
echo "=========================================="
echo " NovaPay Payment Service created"
echo "=========================================="
echo ""
echo "Location:"
echo "$APP_DIR"
echo ""
echo "Next:"
echo "cd $APP_DIR"
echo "python3 -m venv venv"
echo "source venv/bin/activate"
echo "python3 -m pip install -r requirements.txt"
echo "python3 -m pytest -v"
echo ""
