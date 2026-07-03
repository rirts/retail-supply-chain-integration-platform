from __future__ import annotations

import argparse
import json
import os
import uuid
from pathlib import Path
from typing import Any

import psycopg
from confluent_kafka import Consumer, KafkaException
from dotenv import load_dotenv
from psycopg.types.json import Jsonb


PROJECT_ROOT = Path(__file__).resolve().parents[1]

BOOTSTRAP_SERVERS = "localhost:19092"
TOPIC_NAME = "inventory-events"
SOURCE_SYSTEM = "warehouse_event_stream"


def get_connection() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")

    return psycopg.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "integration_platform"),
        user=os.getenv("POSTGRES_USER", "integration_user"),
        password=os.getenv("POSTGRES_PASSWORD", "integration_password"),
    )


def create_event_batch(conn: psycopg.Connection, expected_count: int | None) -> str:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into monitoring.batch_audit_log (
                pipeline_name,
                source_system,
                entity_name,
                batch_type,
                source_reference,
                source_count,
                accepted_count,
                rejected_count,
                loaded_count,
                status
            )
            values (
                'inventory_event_stream_ingestion',
                %(source_system)s,
                'inventory_events',
                'EVENT_STREAM',
                %(source_reference)s,
                %(source_count)s,
                0,
                0,
                0,
                'RAW_LOADED'
            )
            returning batch_id::text;
            """,
            {
                "source_system": SOURCE_SYSTEM,
                "source_reference": TOPIC_NAME,
                "source_count": expected_count or 0,
            },
        )

        return cur.fetchone()[0]


def insert_event_raw(
    conn: psycopg.Connection,
    batch_id: str,
    event_id: str | None,
    raw_payload: dict[str, Any],
) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into raw.inventory_events_raw (
                event_id,
                batch_id,
                topic_name,
                source_system,
                raw_payload
            )
            values (
                %(event_id)s,
                %(batch_id)s,
                %(topic_name)s,
                %(source_system)s,
                %(raw_payload)s
            )
            on conflict (event_id)
            where event_id is not null
            do nothing;
            """,
            {
                "event_id": event_id,
                "batch_id": batch_id,
                "topic_name": TOPIC_NAME,
                "source_system": SOURCE_SYSTEM,
                "raw_payload": Jsonb(raw_payload),
            },
        )

        return cur.rowcount == 1


def insert_duplicate_event_rejection(
    conn: psycopg.Connection,
    batch_id: str,
    event_id: str | None,
    raw_payload: dict[str, Any],
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into monitoring.rejected_records (
                batch_id,
                source_system,
                entity_name,
                record_key,
                raw_payload,
                rejection_stage,
                rejection_reason
            )
            values (
                %(batch_id)s,
                %(source_system)s,
                'inventory_events',
                %(record_key)s,
                %(raw_payload)s,
                'EVENT_DEDUPLICATION',
                'event_id is duplicated; duplicate event ignored at raw ingestion'
            );
            """,
            {
                "batch_id": batch_id,
                "source_system": SOURCE_SYSTEM,
                "record_key": event_id,
                "raw_payload": Jsonb(raw_payload),
            },
        )


def consume_events(max_messages: int, timeout_seconds: int) -> None:
    consumer = Consumer(
        {
            "bootstrap.servers": BOOTSTRAP_SERVERS,
            "group.id": f"inventory-raw-loader-{uuid.uuid4()}",
            "auto.offset.reset": "earliest",
            "enable.auto.commit": False,
        }
    )

    consumed_count = 0
    inserted_count = 0
    duplicate_count = 0

    consumer.subscribe([TOPIC_NAME])

    with get_connection() as conn:
        with conn.transaction():
            batch_id = create_event_batch(conn, expected_count=max_messages)

        try:
            while consumed_count < max_messages:
                msg = consumer.poll(timeout_seconds)

                if msg is None:
                    print("No more messages available before timeout.")
                    break

                if msg.error():
                    raise KafkaException(msg.error())

                consumed_count += 1

                try:
                    payload = json.loads(msg.value().decode("utf-8"))
                except json.JSONDecodeError:
                    payload = {
                        "raw_message": msg.value().decode("utf-8", errors="replace"),
                        "parse_error": "invalid_json",
                    }

                event_id = payload.get("event_id")

                with conn.transaction():
                    inserted = insert_event_raw(
                        conn=conn,
                        batch_id=batch_id,
                        event_id=event_id,
                        raw_payload=payload,
                    )

                    if not inserted:
                        insert_duplicate_event_rejection(
                            conn=conn,
                            batch_id=batch_id,
                            event_id=event_id,
                            raw_payload=payload,
                        )

                if inserted:
                    inserted_count += 1
                else:
                    duplicate_count += 1

            with conn.transaction():
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        update monitoring.batch_audit_log
                        set
                            source_count = %(source_count)s,
                            error_message = %(error_message)s,
                            updated_at = now()
                        where batch_id = %(batch_id)s;
                        """,
                        {
                            "batch_id": batch_id,
                            "source_count": consumed_count,
                            "error_message": (
                                f"raw_inserted={inserted_count}; "
                                f"duplicates_ignored={duplicate_count}"
                            ),
                        },
                    )

        finally:
            consumer.close()

    print(
        f"Consumed inventory events: "
        f"batch_id={batch_id}, "
        f"consumed_count={consumed_count}, "
        f"raw_inserted={inserted_count}, "
        f"duplicates_ignored={duplicate_count}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Consume inventory events from Redpanda into PostgreSQL raw.inventory_events_raw."
    )

    parser.add_argument("--max-messages", type=int, default=206)
    parser.add_argument("--timeout-seconds", type=int, default=5)

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    consume_events(
        max_messages=args.max_messages,
        timeout_seconds=args.timeout_seconds,
    )


if __name__ == "__main__":
    main()