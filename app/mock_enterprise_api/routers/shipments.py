from __future__ import annotations

from fastapi import APIRouter, Query

from services.mock_data import SHIPMENTS, paginate_records


router = APIRouter(prefix="/api/v1/shipments", tags=["shipments"])


@router.get("")
def get_shipments(
    updated_since: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    include_bad_records: bool = Query(default=True),
) -> dict:
    return paginate_records(
        records=SHIPMENTS,
        updated_since=updated_since,
        limit=limit,
        offset=offset,
        include_bad_records=include_bad_records,
    )