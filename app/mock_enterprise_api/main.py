from datetime import datetime, timezone

from fastapi import FastAPI


app = FastAPI(
    title="Retail Supply Chain Mock Enterprise API",
    version="0.1.0",
    description=(
        "Mock enterprise API used to simulate sales orders, purchase orders, "
        "shipments, and supply chain planning integrations."
    ),
)


@app.get("/")
def root() -> dict:
    return {
        "service": "retail-supply-chain-mock-api",
        "status": "running",
        "docs_url": "/docs",
    }


@app.get("/health")
def health_check() -> dict:
    return {
        "status": "ok",
        "service": "mock_enterprise_api",
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }