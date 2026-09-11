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
