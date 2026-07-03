from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import psycopg
import requests
from dotenv import load_dotenv
from psycopg.types.json import Jsonb


PROJECT_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class ApiEntityConfig:
    entity_name: str
    endpoint: str
    pipeline_name: str


API_ENTITY_CONFIGS: dict[str, ApiEntityConfig] = {
    "sales_orders": ApiEntityConfig(
        entity_name="sales_orders",
        endpoint="/api/v1/sales-orders",
        pipeline_name="api_sales_orders_integration",
    ),
    "purchase_orders": ApiEntityConfig(
        entity_name="purchase_orders",
        endpoint="/api/v1/purchase-orders",
        pipeline_name="api_purchase_orders_integration",
    ),
    "shipments": ApiEntityConfig(
        entity_name="shipments",
        endpoint="/api/v1/shipments",
        pipeline_name="api_shipments_integration",
    ),
}


def get_connection() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")

    return psycopg.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.getenv("POSTGRES_DB", "integration_platform"),
        user=os.getenv("POSTGRES_USER", "integration_user"),
        password=os.getenv("POSTGRES_PASSWORD", "integration_password"),
    )


def get_api_base_url() -> str:
    return os.getenv("MOCK_API_BASE_URL", "http://localhost:8000").rstrip("/")


def fetch_all_records(
    api_base_url: str,
    entity_config: ApiEntityConfig,
    limit: int,
    updated_since: str | None,
    include_bad_records: bool,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    all_records: list[dict[str, Any]] = []
    offset = 0
    total_count: int | None = None

    while True:
        params = {
            "limit": limit,
            "offset": offset,
            "include_bad_records": str(include_bad_records).lower(),
        }

        if updated_since:
            params["updated_since"] = updated_since

        response = requests.get(
            f"{api_base_url}{entity_config.endpoint}",
            params=params,
            timeout=30,
        )
        response.raise_for_status()

        payload = response.json()

        if total_count is None:
            total_count = payload["count"]

        all_records.extend(payload["data"])

        next_offset = payload.get("next_offset")

        if next_offset is None:
            break

        offset = next_offset

    request_params = {
        "limit": limit,
        "updated_since": updated_since,
        "include_bad_records": include_bad_records,
        "source_reported_count": total_count,
    }

    return all_records, request_params


def create_batch_audit_log(
    conn: psycopg.Connection,
    entity_config: ApiEntityConfig,
    source_count: int,
    source_system: str,
    source_reference: str,
) -> str:
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
                %(pipeline_name)s,
                %(source_system)s,
                %(entity_name)s,
                'API',
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
                "pipeline_name": entity_config.pipeline_name,
                "source_system": source_system,
                "entity_name": entity_config.entity_name,
                "source_reference": source_reference,
                "source_count": source_count,
            },
        )

        return cur.fetchone()[0]


def insert_api_raw_records(
    conn: psycopg.Connection,
    batch_id: str,
    entity_config: ApiEntityConfig,
    records: list[dict[str, Any]],
    request_params: dict[str, Any],
    source_system: str,
) -> int:
    payloads = [
        {
            "batch_id": batch_id,
            "source_system": source_system,
            "entity_name": entity_config.entity_name,
            "endpoint": entity_config.endpoint,
            "request_params": Jsonb(request_params),
            "raw_payload": Jsonb(record),
        }
        for record in records
    ]

    with conn.cursor() as cur:
        cur.executemany(
            """
            insert into raw.api_ingestion_raw (
                batch_id,
                source_system,
                entity_name,
                endpoint,
                request_params,
                raw_payload
            )
            values (
                %(batch_id)s,
                %(source_system)s,
                %(entity_name)s,
                %(endpoint)s,
                %(request_params)s,
                %(raw_payload)s
            );
            """,
            payloads,
        )

    return len(payloads)


def load_entity(
    conn: psycopg.Connection,
    entity_config: ApiEntityConfig,
    limit: int,
    updated_since: str | None,
    include_bad_records: bool,
    source_system: str,
) -> None:
    api_base_url = get_api_base_url()

    records, request_params = fetch_all_records(
        api_base_url=api_base_url,
        entity_config=entity_config,
        limit=limit,
        updated_since=updated_since,
        include_bad_records=include_bad_records,
    )

    with conn.transaction():
        batch_id = create_batch_audit_log(
            conn=conn,
            entity_config=entity_config,
            source_count=len(records),
            source_system=source_system,
            source_reference=f"{api_base_url}{entity_config.endpoint}",
        )

        inserted_count = insert_api_raw_records(
            conn=conn,
            batch_id=batch_id,
            entity_config=entity_config,
            records=records,
            request_params=request_params,
            source_system=source_system,
        )

    print(
        f"Loaded API raw {entity_config.entity_name}: "
        f"batch_id={batch_id}, "
        f"source_count={len(records)}, "
        f"raw_inserted={inserted_count}, "
        f"endpoint={entity_config.endpoint}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Load mock enterprise API data into PostgreSQL raw tables."
    )

    parser.add_argument(
        "--entity",
        choices=[*API_ENTITY_CONFIGS.keys(), "all"],
        default="all",
    )

    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--updated-since", default=None)
    parser.add_argument(
        "--exclude-bad-records",
        action="store_true",
        help="Call API with include_bad_records=false.",
    )
    parser.add_argument(
        "--source-system",
        default="mock_enterprise_api",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    selected_entities = (
        API_ENTITY_CONFIGS.values()
        if args.entity == "all"
        else [API_ENTITY_CONFIGS[args.entity]]
    )

    with get_connection() as conn:
        for entity_config in selected_entities:
            load_entity(
                conn=conn,
                entity_config=entity_config,
                limit=args.limit,
                updated_since=args.updated_since,
                include_bad_records=not args.exclude_bad_records,
                source_system=args.source_system,
            )


if __name__ == "__main__":
    main()