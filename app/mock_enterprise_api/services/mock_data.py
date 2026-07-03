from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone
from typing import Any


BASE_TIME = datetime(2026, 7, 1, 8, 0, 0, tzinfo=timezone.utc)

PRODUCT_IDS = [f"PROD-{i:05d}" for i in range(1, 201)]
SUPPLIER_IDS = [f"SUP-{i:04d}" for i in range(1, 21)]
STORE_IDS = [f"STORE-{i:04d}" for i in range(1, 36)]
DC_IDS = [f"DC-{i:04d}" for i in range(1, 8)]
WAREHOUSE_IDS = [f"WH-{i:04d}" for i in range(1, 8)]

CHANNELS = ["ECOMMERCE", "RETAIL_STORE", "WHOLESALE"]
SALES_ORDER_STATUSES = ["CREATED", "CONFIRMED", "ALLOCATED", "SHIPPED", "CANCELLED"]
PURCHASE_ORDER_STATUSES = ["CREATED", "APPROVED", "IN_TRANSIT", "RECEIVED", "CANCELLED"]
SHIPMENT_STATUSES = ["CREATED", "PICKED_UP", "IN_TRANSIT", "DELIVERED", "CANCELLED"]
CARRIERS = ["DHL", "FEDEX", "UPS", "ESTAFETA", "LOCAL_CARRIER"]


def iso(dt: datetime) -> str:
    return dt.isoformat()


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None

    normalized = value.replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)

    return parsed


def paginate_records(
    records: list[dict[str, Any]],
    updated_since: str | None,
    limit: int,
    offset: int,
    include_bad_records: bool,
) -> dict[str, Any]:
    parsed_updated_since = parse_datetime(updated_since)

    filtered_records = records

    if not include_bad_records:
        filtered_records = [
            record for record in filtered_records
            if not record.get("_is_bad_record", False)
        ]

    if parsed_updated_since:
        filtered_records = [
            record for record in filtered_records
            if parse_datetime(record["updated_at"]) >= parsed_updated_since
        ]

    total_count = len(filtered_records)
    page = filtered_records[offset: offset + limit]
    next_offset = offset + limit if offset + limit < total_count else None

    cleaned_page = [
        {key: value for key, value in record.items() if key != "_is_bad_record"}
        for record in page
    ]

    return {
        "count": total_count,
        "limit": limit,
        "offset": offset,
        "next_offset": next_offset,
        "data": cleaned_page,
    }


def generate_sales_orders() -> list[dict[str, Any]]:
    random.seed(101)
    records: list[dict[str, Any]] = []

    for i in range(1, 301):
        order_date = BASE_TIME + timedelta(hours=i)
        requested_ship_date = order_date + timedelta(days=random.randint(1, 7))

        records.append(
            {
                "sales_order_id": f"SO-{i:06d}",
                "sales_order_line_id": f"SO-{i:06d}-LINE-001",
                "product_id": random.choice(PRODUCT_IDS),
                "location_id": random.choice(STORE_IDS),
                "customer_channel": random.choice(CHANNELS),
                "order_status": random.choice(SALES_ORDER_STATUSES),
                "order_date": iso(order_date),
                "requested_ship_date": iso(requested_ship_date),
                "quantity_ordered": random.randint(1, 20),
                "unit_price": round(random.uniform(15.00, 180.00), 2),
                "updated_at": iso(order_date + timedelta(minutes=random.randint(5, 240))),
                "_is_bad_record": False,
            }
        )

    records.extend(
        [
            {
                "sales_order_id": "SO-BAD-PRODUCT",
                "sales_order_line_id": "SO-BAD-PRODUCT-LINE-001",
                "product_id": "PROD-99999",
                "location_id": "STORE-0001",
                "customer_channel": "ECOMMERCE",
                "order_status": "CONFIRMED",
                "order_date": iso(BASE_TIME),
                "requested_ship_date": iso(BASE_TIME + timedelta(days=2)),
                "quantity_ordered": 3,
                "unit_price": 59.99,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
            {
                "sales_order_id": "SO-BAD-QTY",
                "sales_order_line_id": "SO-BAD-QTY-LINE-001",
                "product_id": "PROD-00010",
                "location_id": "STORE-0002",
                "customer_channel": "RETAIL_STORE",
                "order_status": "CONFIRMED",
                "order_date": iso(BASE_TIME),
                "requested_ship_date": iso(BASE_TIME + timedelta(days=2)),
                "quantity_ordered": 0,
                "unit_price": 29.99,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
            {
                "sales_order_id": "SO-BAD-STATUS",
                "sales_order_line_id": "SO-BAD-STATUS-LINE-001",
                "product_id": "PROD-00020",
                "location_id": "STORE-0003",
                "customer_channel": "ECOMMERCE",
                "order_status": "UNKNOWN_STATUS",
                "order_date": iso(BASE_TIME),
                "requested_ship_date": iso(BASE_TIME + timedelta(days=2)),
                "quantity_ordered": 2,
                "unit_price": 39.99,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
        ]
    )

    return records


def generate_purchase_orders() -> list[dict[str, Any]]:
    random.seed(202)
    records: list[dict[str, Any]] = []

    for i in range(1, 151):
        order_date = BASE_TIME + timedelta(hours=i * 2)
        expected_delivery_date = order_date + timedelta(days=random.randint(3, 21))

        records.append(
            {
                "purchase_order_id": f"PO-{i:06d}",
                "purchase_order_line_id": f"PO-{i:06d}-LINE-001",
                "supplier_id": random.choice(SUPPLIER_IDS),
                "product_id": random.choice(PRODUCT_IDS),
                "destination_location_id": random.choice(DC_IDS + WAREHOUSE_IDS),
                "purchase_order_status": random.choice(PURCHASE_ORDER_STATUSES),
                "order_date": iso(order_date),
                "expected_delivery_date": iso(expected_delivery_date),
                "quantity_ordered": random.randint(50, 2000),
                "unit_cost": round(random.uniform(5.00, 120.00), 2),
                "updated_at": iso(order_date + timedelta(minutes=random.randint(30, 360))),
                "_is_bad_record": False,
            }
        )

    records.extend(
        [
            {
                "purchase_order_id": "PO-BAD-SUPPLIER",
                "purchase_order_line_id": "PO-BAD-SUPPLIER-LINE-001",
                "supplier_id": "SUP-9999",
                "product_id": "PROD-00010",
                "destination_location_id": "DC-0001",
                "purchase_order_status": "APPROVED",
                "order_date": iso(BASE_TIME),
                "expected_delivery_date": iso(BASE_TIME + timedelta(days=10)),
                "quantity_ordered": 500,
                "unit_cost": 25.50,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
            {
                "purchase_order_id": "PO-BAD-DATE",
                "purchase_order_line_id": "PO-BAD-DATE-LINE-001",
                "supplier_id": "SUP-0001",
                "product_id": "PROD-00011",
                "destination_location_id": "DC-0002",
                "purchase_order_status": "APPROVED",
                "order_date": iso(BASE_TIME + timedelta(days=5)),
                "expected_delivery_date": iso(BASE_TIME + timedelta(days=1)),
                "quantity_ordered": 300,
                "unit_cost": 18.00,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
            {
                "purchase_order_id": "PO-BAD-COST",
                "purchase_order_line_id": "PO-BAD-COST-LINE-001",
                "supplier_id": "SUP-0002",
                "product_id": "PROD-00012",
                "destination_location_id": "DC-0003",
                "purchase_order_status": "APPROVED",
                "order_date": iso(BASE_TIME),
                "expected_delivery_date": iso(BASE_TIME + timedelta(days=5)),
                "quantity_ordered": 300,
                "unit_cost": -18.00,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
        ]
    )

    return records


def generate_shipments() -> list[dict[str, Any]]:
    random.seed(303)
    records: list[dict[str, Any]] = []

    for i in range(1, 181):
        shipped_at = BASE_TIME + timedelta(hours=i * 3)
        delivered_at = shipped_at + timedelta(days=random.randint(1, 8))

        related_order_type = random.choice(["SALES_ORDER", "PURCHASE_ORDER"])
        related_order_id = (
            f"SO-{random.randint(1, 300):06d}"
            if related_order_type == "SALES_ORDER"
            else f"PO-{random.randint(1, 150):06d}"
        )

        records.append(
            {
                "shipment_id": f"SHP-{i:06d}",
                "related_order_type": related_order_type,
                "related_order_id": related_order_id,
                "product_id": random.choice(PRODUCT_IDS),
                "origin_location_id": random.choice(DC_IDS + WAREHOUSE_IDS),
                "destination_location_id": random.choice(STORE_IDS + DC_IDS),
                "carrier": random.choice(CARRIERS),
                "shipment_status": random.choice(SHIPMENT_STATUSES),
                "shipped_at": iso(shipped_at),
                "delivered_at": iso(delivered_at),
                "quantity_shipped": random.randint(1, 500),
                "updated_at": iso(shipped_at + timedelta(minutes=random.randint(30, 600))),
                "_is_bad_record": False,
            }
        )

    records.extend(
        [
            {
                "shipment_id": "SHP-BAD-DATE",
                "related_order_type": "SALES_ORDER",
                "related_order_id": "SO-000001",
                "product_id": "PROD-00010",
                "origin_location_id": "DC-0001",
                "destination_location_id": "STORE-0001",
                "carrier": "DHL",
                "shipment_status": "DELIVERED",
                "shipped_at": iso(BASE_TIME + timedelta(days=5)),
                "delivered_at": iso(BASE_TIME + timedelta(days=2)),
                "quantity_shipped": 10,
                "updated_at": iso(BASE_TIME + timedelta(days=6)),
                "_is_bad_record": True,
            },
            {
                "shipment_id": "SHP-BAD-LOCATION",
                "related_order_type": "SALES_ORDER",
                "related_order_id": "SO-000002",
                "product_id": "PROD-00020",
                "origin_location_id": "DC-9999",
                "destination_location_id": "STORE-0002",
                "carrier": "FEDEX",
                "shipment_status": "IN_TRANSIT",
                "shipped_at": iso(BASE_TIME),
                "delivered_at": None,
                "quantity_shipped": 20,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
            {
                "shipment_id": "SHP-BAD-QTY",
                "related_order_type": "PURCHASE_ORDER",
                "related_order_id": "PO-000001",
                "product_id": "PROD-00030",
                "origin_location_id": "WH-0001",
                "destination_location_id": "DC-0002",
                "carrier": "UPS",
                "shipment_status": "IN_TRANSIT",
                "shipped_at": iso(BASE_TIME),
                "delivered_at": None,
                "quantity_shipped": -5,
                "updated_at": iso(BASE_TIME + timedelta(days=1)),
                "_is_bad_record": True,
            },
        ]
    )

    return records


SALES_ORDERS = generate_sales_orders()
PURCHASE_ORDERS = generate_purchase_orders()
SHIPMENTS = generate_shipments()