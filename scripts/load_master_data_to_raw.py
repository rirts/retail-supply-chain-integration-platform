from __future__ import annotations

import argparse
import csv
import os
from dataclasses import dataclass
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg.types.json import Jsonb


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INBOUND_DIR = PROJECT_ROOT / "data" / "inbound"


@dataclass(frozen=True)
class EntityConfig:
    entity_name: str
    folder_name: str
    pipeline_name: str


ENTITY_CONFIGS: dict[str, EntityConfig] = {
    "suppliers": EntityConfig(
        entity_name="suppliers",
        folder_name="suppliers",
        pipeline_name="flat_file_suppliers_master_data",
    ),
    "products": EntityConfig(
        entity_name="products",
        folder_name="products",
        pipeline_name="flat_file_products_master_data",
    ),
    "locations": EntityConfig(
        entity_name="locations",
        folder_name="locations",
        pipeline_name="flat_file_locations_master_data",
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


def find_latest_file(entity_config: EntityConfig, batch_date: str | None) -> Path:
    entity_dir = INBOUND_DIR / entity_config.folder_name

    if batch_date:
        matching_files = sorted(entity_dir.glob(f"{entity_config.entity_name}_{batch_date}.csv"))
    else:
        matching_files = sorted(
            entity_dir.glob(f"{entity_config.entity_name}_*.csv"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )

    if not matching_files:
        date_message = f" for date {batch_date}" if batch_date else ""
        raise FileNotFoundError(
            f"No CSV file found for entity '{entity_config.entity_name}'{date_message} "
            f"in {entity_dir}"
        )

    return matching_files[0]


def read_csv_rows(file_path: Path) -> list[tuple[int, dict[str, str]]]:
    rows: list[tuple[int, dict[str, str]]] = []

    with file_path.open("r", newline="", encoding="utf-8") as csv_file:
        reader = csv.DictReader(csv_file)

        for row_number, row in enumerate(reader, start=2):
            cleaned_row = {
                key: value.strip() if isinstance(value, str) else value
                for key, value in row.items()
            }
            rows.append((row_number, cleaned_row))

    return rows


def create_batch_audit_log(
    conn: psycopg.Connection,
    entity_config: EntityConfig,
    source_file: Path,
    source_count: int,
    source_system: str,
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
                'FLAT_FILE',
                %(source_reference)s,
                %(source_count)s,
                0,
                0,
                0,
                'STARTED'
            )
            returning batch_id::text;
            """,
            {
                "pipeline_name": entity_config.pipeline_name,
                "source_system": source_system,
                "entity_name": entity_config.entity_name,
                "source_reference": str(source_file.relative_to(PROJECT_ROOT)).replace("\\", "/"),
                "source_count": source_count,
            },
        )

        batch_id = cur.fetchone()[0]

    return batch_id


def insert_raw_rows(
    conn: psycopg.Connection,
    batch_id: str,
    entity_config: EntityConfig,
    source_file: Path,
    rows: list[tuple[int, dict[str, str]]],
    source_system: str,
) -> int:
    records = [
        {
            "batch_id": batch_id,
            "source_system": source_system,
            "entity_name": entity_config.entity_name,
            "source_file_name": source_file.name,
            "row_number": row_number,
            "raw_payload": Jsonb(row),
        }
        for row_number, row in rows
    ]

    with conn.cursor() as cur:
        cur.executemany(
            """
            insert into raw.file_ingestion_raw (
                batch_id,
                source_system,
                entity_name,
                source_file_name,
                row_number,
                raw_payload
            )
            values (
                %(batch_id)s,
                %(source_system)s,
                %(entity_name)s,
                %(source_file_name)s,
                %(row_number)s,
                %(raw_payload)s
            );
            """,
            records,
        )

    return len(records)


def load_entity(
    conn: psycopg.Connection,
    entity_config: EntityConfig,
    batch_date: str | None,
    source_system: str,
) -> None:
    source_file = find_latest_file(entity_config, batch_date)
    rows = read_csv_rows(source_file)

    with conn.transaction():
        batch_id = create_batch_audit_log(
            conn=conn,
            entity_config=entity_config,
            source_file=source_file,
            source_count=len(rows),
            source_system=source_system,
        )

        inserted_count = insert_raw_rows(
            conn=conn,
            batch_id=batch_id,
            entity_config=entity_config,
            source_file=source_file,
            rows=rows,
            source_system=source_system,
        )

    print(
        f"Loaded {entity_config.entity_name}: "
        f"batch_id={batch_id}, "
        f"source_count={len(rows)}, "
        f"raw_inserted={inserted_count}, "
        f"file={source_file.relative_to(PROJECT_ROOT)}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Load generated master data CSV files into PostgreSQL raw tables."
    )

    parser.add_argument(
        "--entity",
        choices=[*ENTITY_CONFIGS.keys(), "all"],
        default="all",
        help="Entity to load. Defaults to all.",
    )

    parser.add_argument(
        "--batch-date",
        help="Optional batch date in YYYYMMDD format. If omitted, the latest file is used.",
    )

    parser.add_argument(
        "--source-system",
        default="erp_flat_file",
        help="Source system name stored in raw/audit metadata.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    selected_entities = (
        ENTITY_CONFIGS.values()
        if args.entity == "all"
        else [ENTITY_CONFIGS[args.entity]]
    )

    with get_connection() as conn:
        for entity_config in selected_entities:
            load_entity(
                conn=conn,
                entity_config=entity_config,
                batch_date=args.batch_date,
                source_system=args.source_system,
            )


if __name__ == "__main__":
    main()