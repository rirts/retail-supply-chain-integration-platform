from __future__ import annotations

import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv


PROJECT_ROOT = Path(__file__).resolve().parents[1]

ENTITY_ORDER = ["suppliers", "locations", "products"]


def get_connection() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")

    return psycopg.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "integration_platform"),
        user=os.getenv("POSTGRES_USER", "integration_user"),
        password=os.getenv("POSTGRES_PASSWORD", "integration_password"),
    )


def get_latest_batch_id(conn: psycopg.Connection, entity_name: str) -> str:
    with conn.cursor() as cur:
        cur.execute(
            """
            select batch_id::text
            from monitoring.batch_audit_log
            where entity_name = %s
              and batch_type = 'FLAT_FILE'
            order by created_at desc
            limit 1;
            """,
            (entity_name,),
        )

        row = cur.fetchone()

    if not row:
        raise RuntimeError(f"No flat-file batch found for entity: {entity_name}")

    return row[0]


def validate_batch(conn: psycopg.Connection, batch_id: str) -> dict:
    with conn.cursor() as cur:
        cur.execute(
            """
            select
                result_batch_id::text,
                result_entity_name,
                result_source_count,
                result_accepted_count,
                result_rejected_count,
                result_status
            from monitoring.validate_flat_file_master_data_batch(%s);
            """,
            (batch_id,),
        )

        row = cur.fetchone()

    if not row:
        raise RuntimeError(f"Validation returned no result for batch_id: {batch_id}")

    return {
        "batch_id": row[0],
        "entity_name": row[1],
        "source_count": row[2],
        "accepted_count": row[3],
        "rejected_count": row[4],
        "status": row[5],
    }


def main() -> None:
    with get_connection() as conn:
        for entity_name in ENTITY_ORDER:
            batch_id = get_latest_batch_id(conn, entity_name)
            result = validate_batch(conn, batch_id)
            conn.commit()

            print(
                f"Validated {result['entity_name']}: "
                f"batch_id={result['batch_id']}, "
                f"source_count={result['source_count']}, "
                f"accepted_count={result['accepted_count']}, "
                f"rejected_count={result['rejected_count']}, "
                f"status={result['status']}"
            )


if __name__ == "__main__":
    main()