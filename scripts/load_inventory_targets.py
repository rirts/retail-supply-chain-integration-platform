from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def get_connection() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")

    return psycopg.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "integration_platform"),
        user=os.getenv("POSTGRES_USER", "integration_user"),
        password=os.getenv("POSTGRES_PASSWORD", "integration_password"),
    )


def get_latest_validated_event_batch_id(conn: psycopg.Connection) -> str:
    with conn.cursor() as cur:
        cur.execute(
            """
            select batch_id::text
            from monitoring.batch_audit_log
            where entity_name = 'inventory_events'
              and batch_type = 'EVENT_STREAM'
              and status = 'VALIDATED'
            order by created_at desc
            limit 1;
            """
        )

        row = cur.fetchone()

    if not row:
        raise RuntimeError("No VALIDATED inventory_events batch found.")

    return row[0]


def load_target_batch(conn: psycopg.Connection, batch_id: str) -> dict:
    with conn.cursor() as cur:
        cur.execute(
            """
            select
                result_batch_id::text,
                result_entity_name,
                result_source_count,
                result_accepted_count,
                result_rejected_count,
                result_loaded_count,
                result_reconciliation_status,
                result_batch_status
            from target.load_validated_inventory_event_batch(%s);
            """,
            (batch_id,),
        )

        row = cur.fetchone()

    if not row:
        raise RuntimeError(f"Target load returned no result for batch_id: {batch_id}")

    return {
        "batch_id": row[0],
        "entity_name": row[1],
        "source_count": row[2],
        "accepted_count": row[3],
        "rejected_count": row[4],
        "loaded_count": row[5],
        "reconciliation_status": row[6],
        "batch_status": row[7],
    }


def main() -> None:
    with get_connection() as conn:
        batch_id = get_latest_validated_event_batch_id(conn)
        result = load_target_batch(conn, batch_id)
        conn.commit()

    print(
        f"Loaded inventory targets: "
        f"batch_id={result['batch_id']}, "
        f"source_count={result['source_count']}, "
        f"accepted_count={result['accepted_count']}, "
        f"rejected_count={result['rejected_count']}, "
        f"loaded_count={result['loaded_count']}, "
        f"reconciliation_status={result['reconciliation_status']}, "
        f"batch_status={result['batch_status']}"
    )


if __name__ == "__main__":
    main()