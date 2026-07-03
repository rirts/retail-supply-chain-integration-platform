from __future__ import annotations

import argparse
import json
import random
import time
from datetime import datetime, timedelta, timezone
from typing import Any

from confluent_kafka import Producer


BOOTSTRAP_SERVERS = "localhost:19092"
TOPIC_NAME = "inventory-events"

BASE_TIME = datetime(2026, 7, 1, 8, 0, 0, tzinfo=timezone.utc)

PRODUCT_IDS = [f"PROD-{i:05d}" for i in range(1, 201)]
LOCATION_IDS = (
    [f"STORE-{i:04d}" for i in range(1, 36)]
    + [f"DC-{i:04d}" for i in range(1, 8)]
    + [f"WH-{i:04d}" for i in range(1, 8)]
)

EVENT_TYPES = [
    "INVENTORY_RECEIVED",
    "INVENTORY_ADJUSTED",
    "INVENTORY_TRANSFERRED",
    "INVENTORY_RESERVED",
    "INVENTORY_RELEASED",
]

REASON_CODES = [
    "PURCHASE_ORDER_RECEIPT",
    "SALES_ORDER_RESERVATION",
    "CYCLE_COUNT_ADJUSTMENT",
    "TRANSFER_OUT",
    "TRANSFER_IN",
    "DAMAGED_GOODS",
]


def iso(dt: datetime) -> str:
    return dt.isoformat()


def build_valid_event(index: int) -> dict[str, Any]:
    event_type = random.choice(EVENT_TYPES)

    if event_type in {"INVENTORY_RECEIVED", "INVENTORY_RELEASED"}:
        quantity_change = random.randint(1, 250)
    elif event_type in {"INVENTORY_RESERVED", "INVENTORY_TRANSFERRED"}:
        quantity_change = -random.randint(1, 100)
    else:
        quantity_change = random.randint(-50, 50) or 1

    event_timestamp = BASE_TIME + timedelta(minutes=index * 5)

    return {
        "event_id": f"INV-EVT-{index:06d}",
        "event_type": event_type,
        "product_id": random.choice(PRODUCT_IDS),
        "location_id": random.choice(LOCATION_IDS),
        "quantity_change": quantity_change,
        "reason_code": random.choice(REASON_CODES),
        "source_system": "warehouse_event_stream",
        "event_timestamp": iso(event_timestamp),
        "published_at": iso(event_timestamp + timedelta(seconds=random.randint(1, 120))),
    }


def build_bad_events() -> list[dict[str, Any]]:
    return [
        {
            "event_id": "INV-EVT-BAD-PRODUCT",
            "event_type": "INVENTORY_ADJUSTED",
            "product_id": "PROD-99999",
            "location_id": "STORE-0001",
            "quantity_change": 10,
            "reason_code": "CYCLE_COUNT_ADJUSTMENT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=20)),
        },
        {
            "event_id": "INV-EVT-BAD-LOCATION",
            "event_type": "INVENTORY_RECEIVED",
            "product_id": "PROD-00010",
            "location_id": "STORE-9999",
            "quantity_change": 25,
            "reason_code": "PURCHASE_ORDER_RECEIPT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=30)),
        },
        {
            "event_id": "INV-EVT-BAD-TYPE",
            "event_type": "INVENTORY_TELEPORTED",
            "product_id": "PROD-00011",
            "location_id": "STORE-0002",
            "quantity_change": 5,
            "reason_code": "CYCLE_COUNT_ADJUSTMENT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=40)),
        },
        {
            "event_id": "INV-EVT-BAD-QTY",
            "event_type": "INVENTORY_ADJUSTED",
            "product_id": "PROD-00012",
            "location_id": "STORE-0003",
            "quantity_change": 0,
            "reason_code": "CYCLE_COUNT_ADJUSTMENT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=50)),
        },
        {
            "event_id": "INV-EVT-DUPLICATE",
            "event_type": "INVENTORY_RECEIVED",
            "product_id": "PROD-00013",
            "location_id": "DC-0001",
            "quantity_change": 50,
            "reason_code": "PURCHASE_ORDER_RECEIPT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=60)),
        },
        {
            "event_id": "INV-EVT-DUPLICATE",
            "event_type": "INVENTORY_RECEIVED",
            "product_id": "PROD-00013",
            "location_id": "DC-0001",
            "quantity_change": 50,
            "reason_code": "PURCHASE_ORDER_RECEIPT",
            "source_system": "warehouse_event_stream",
            "event_timestamp": iso(BASE_TIME + timedelta(days=1)),
            "published_at": iso(BASE_TIME + timedelta(days=1, seconds=65)),
        },
    ]


def delivery_report(err, msg) -> None:
    if err is not None:
        print(f"Delivery failed: {err}")
    else:
        print(
            f"Delivered event to topic={msg.topic()} "
            f"partition={msg.partition()} offset={msg.offset()}"
        )


def produce_events(event_count: int, include_bad_events: bool, seed: int, sleep_ms: int) -> None:
    random.seed(seed)

    producer = Producer(
        {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "client.id": "inventory-event-producer",
        }
    )

    events = [build_valid_event(i) for i in range(1, event_count + 1)]

    if include_bad_events:
        events.extend(build_bad_events())

    for event in events:
        event_key = event.get("event_id", "")

        producer.produce(
            topic=TOPIC_NAME,
            key=event_key,
            value=json.dumps(event),
            callback=delivery_report,
        )
        producer.poll(0)

        if sleep_ms > 0:
            time.sleep(sleep_ms / 1000)

    producer.flush()

    print()
    print(f"Produced {len(events)} inventory events to topic '{TOPIC_NAME}'")
    print(f"Valid events requested: {event_count}")
    print(f"Bad events included: {include_bad_events}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Produce inventory events to Redpanda."
    )

    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--sleep-ms", type=int, default=0)
    parser.add_argument(
        "--no-bad-events",
        action="store_true",
        help="Produce only valid events.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    produce_events(
        event_count=args.count,
        include_bad_events=not args.no_bad_events,
        seed=args.seed,
        sleep_ms=args.sleep_ms,
    )


if __name__ == "__main__":
    main()