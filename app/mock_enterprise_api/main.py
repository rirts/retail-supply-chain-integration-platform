from datetime import datetime, timezone

from fastapi import FastAPI

from routers.purchase_orders import router as purchase_orders_router
from routers.sales_orders import router as sales_orders_router
from routers.shipments import router as shipments_router


app = FastAPI(
    title="Retail Supply Chain Mock Enterprise API",
    version="0.2.0",
    description=(
        "Mock enterprise API used to simulate sales orders, purchase orders, "
        "shipments, and supply chain planning integrations."
    ),
)

app.include_router(sales_orders_router)
app.include_router(purchase_orders_router)
app.include_router(shipments_router)


@app.get("/")
def root() -> dict:
    return {
        "service": "retail-supply-chain-mock-api",
        "status": "running",
        "docs_url": "/docs",
        "version": "0.2.0",
    }


@app.get("/health")
def health_check() -> dict:
    return {
        "status": "ok",
        "service": "mock_enterprise_api",
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }