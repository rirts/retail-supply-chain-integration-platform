from __future__ import annotations

import argparse
import csv
import random
from datetime import datetime, timezone
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
INBOUND_DIR = PROJECT_ROOT / "data" / "inbound"

VALID_COUNTRY_CODES = ["US", "MX", "CA", "CN", "VN", "IN"]
VALID_SUPPLIER_STATUSES = ["ACTIVE", "INACTIVE", "ON_HOLD"]
VALID_PRODUCT_STATUSES = ["ACTIVE", "DISCONTINUED", "SEASONAL"]
VALID_LOCATION_TYPES = ["STORE", "DC", "WAREHOUSE"]

PRODUCT_CATEGORIES = [
    "denim",
    "outerwear",
    "footwear",
    "accessories",
    "tops",
    "bottoms",
]

REGIONS = [
    "north_america",
    "latin_america",
    "emea",
    "apac",
]


def utc_batch_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d")


def write_csv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def generate_suppliers(valid_count: int, include_bad_records: bool) -> list[dict]:
    rows: list[dict] = []

    for i in range(1, valid_count + 1):
        supplier_id = f"SUP-{i:04d}"

        rows.append(
            {
                "supplier_id": supplier_id,
                "supplier_name": f"Supplier {i:04d}",
                "country_code": random.choice(VALID_COUNTRY_CODES),
                "supplier_status": random.choice(["ACTIVE", "ACTIVE", "ACTIVE", "ON_HOLD"]),
            }
        )

    if include_bad_records:
        rows.extend(
            [
                {
                    "supplier_id": "SUP-0001",
                    "supplier_name": "Duplicate Supplier ID",
                    "country_code": "US",
                    "supplier_status": "ACTIVE",
                },
                {
                    "supplier_id": "SUP-BAD-NAME",
                    "supplier_name": "",
                    "country_code": "MX",
                    "supplier_status": "ACTIVE",
                },
                {
                    "supplier_id": "SUP-BAD-COUNTRY",
                    "supplier_name": "Invalid Country Supplier",
                    "country_code": "XX",
                    "supplier_status": "ACTIVE",
                },
                {
                    "supplier_id": "SUP-BAD-STATUS",
                    "supplier_name": "Invalid Status Supplier",
                    "country_code": "CA",
                    "supplier_status": "SUSPENDED",
                },
            ]
        )

    return rows


def generate_products(
    valid_count: int,
    supplier_rows: list[dict],
    include_bad_records: bool,
) -> list[dict]:
    rows: list[dict] = []
    valid_supplier_ids = [
        row["supplier_id"]
        for row in supplier_rows
        if row["supplier_id"].startswith("SUP-")
        and row["supplier_id"] not in {"SUP-BAD-NAME", "SUP-BAD-COUNTRY", "SUP-BAD-STATUS"}
    ]

    for i in range(1, valid_count + 1):
        product_id = f"PROD-{i:05d}"

        rows.append(
            {
                "product_id": product_id,
                "sku": f"SKU-{100000 + i}",
                "product_name": f"Retail Product {i:05d}",
                "category": random.choice(PRODUCT_CATEGORIES),
                "supplier_id": random.choice(valid_supplier_ids),
                "unit_cost": f"{random.uniform(5.00, 120.00):.2f}",
                "product_status": random.choice(["ACTIVE", "ACTIVE", "ACTIVE", "SEASONAL"]),
            }
        )

    if include_bad_records:
        rows.extend(
            [
                {
                    "product_id": "PROD-00001",
                    "sku": "SKU-DUPLICATE-PRODUCT",
                    "product_name": "Duplicate Product ID",
                    "category": "denim",
                    "supplier_id": "SUP-0001",
                    "unit_cost": "39.99",
                    "product_status": "ACTIVE",
                },
                {
                    "product_id": "PROD-BAD-SKU",
                    "sku": "",
                    "product_name": "Missing SKU Product",
                    "category": "tops",
                    "supplier_id": "SUP-0002",
                    "unit_cost": "19.99",
                    "product_status": "ACTIVE",
                },
                {
                    "product_id": "PROD-BAD-SUPPLIER",
                    "sku": "SKU-BAD-SUPPLIER",
                    "product_name": "Unknown Supplier Product",
                    "category": "footwear",
                    "supplier_id": "SUP-9999",
                    "unit_cost": "49.99",
                    "product_status": "ACTIVE",
                },
                {
                    "product_id": "PROD-BAD-COST",
                    "sku": "SKU-BAD-COST",
                    "product_name": "Negative Unit Cost Product",
                    "category": "accessories",
                    "supplier_id": "SUP-0003",
                    "unit_cost": "-10.00",
                    "product_status": "ACTIVE",
                },
                {
                    "product_id": "PROD-BAD-STATUS",
                    "sku": "SKU-BAD-STATUS",
                    "product_name": "Invalid Product Status",
                    "category": "outerwear",
                    "supplier_id": "SUP-0004",
                    "unit_cost": "89.99",
                    "product_status": "ARCHIVED",
                },
            ]
        )

    return rows


def generate_locations(valid_count: int, include_bad_records: bool) -> list[dict]:
    rows: list[dict] = []

    required_locations: list[tuple[str, str]] = []

    required_locations.extend(
        [(f"STORE-{i:04d}", "STORE") for i in range(1, 36)]
    )
    required_locations.extend(
        [(f"DC-{i:04d}", "DC") for i in range(1, 8)]
    )
    required_locations.extend(
        [(f"WH-{i:04d}", "WAREHOUSE") for i in range(1, 8)]
    )

    for location_id, location_type in required_locations[:valid_count]:
        rows.append(
            {
                "location_id": location_id,
                "location_name": f"{location_type.title()} {location_id}",
                "location_type": location_type,
                "region": random.choice(REGIONS),
                "country_code": random.choice(VALID_COUNTRY_CODES),
                "location_status": random.choice(["ACTIVE", "ACTIVE", "ACTIVE", "INACTIVE"]),
            }
        )

    next_index = 1
    while len(rows) < valid_count:
        location_id = f"EXTRA-{next_index:04d}"
        rows.append(
            {
                "location_id": location_id,
                "location_name": f"Extra Location {next_index:04d}",
                "location_type": random.choice(VALID_LOCATION_TYPES),
                "region": random.choice(REGIONS),
                "country_code": random.choice(VALID_COUNTRY_CODES),
                "location_status": random.choice(["ACTIVE", "ACTIVE", "ACTIVE", "INACTIVE"]),
            }
        )
        next_index += 1

    if include_bad_records:
        rows.extend(
            [
                {
                    "location_id": "STORE-0001",
                    "location_name": "Duplicate Location ID",
                    "location_type": "STORE",
                    "region": "north_america",
                    "country_code": "US",
                    "location_status": "ACTIVE",
                },
                {
                    "location_id": "LOC-BAD-TYPE",
                    "location_name": "Invalid Type Location",
                    "location_type": "POPUP",
                    "region": "latin_america",
                    "country_code": "MX",
                    "location_status": "ACTIVE",
                },
                {
                    "location_id": "LOC-BAD-COUNTRY",
                    "location_name": "Missing Country Location",
                    "location_type": "STORE",
                    "region": "emea",
                    "country_code": "",
                    "location_status": "ACTIVE",
                },
                {
                    "location_id": "LOC-BAD-STATUS",
                    "location_name": "Invalid Status Location",
                    "location_type": "DC",
                    "region": "apac",
                    "country_code": "VN",
                    "location_status": "CLOSED_FOREVER",
                },
            ]
        )

    return rows


def generate_files(
    supplier_count: int,
    product_count: int,
    location_count: int,
    include_bad_records: bool,
) -> None:
    batch_date = utc_batch_date()

    suppliers = generate_suppliers(
        valid_count=supplier_count,
        include_bad_records=include_bad_records,
    )
    products = generate_products(
        valid_count=product_count,
        supplier_rows=suppliers,
        include_bad_records=include_bad_records,
    )
    locations = generate_locations(
        valid_count=location_count,
        include_bad_records=include_bad_records,
    )

    suppliers_path = INBOUND_DIR / "suppliers" / f"suppliers_{batch_date}.csv"
    products_path = INBOUND_DIR / "products" / f"products_{batch_date}.csv"
    locations_path = INBOUND_DIR / "locations" / f"locations_{batch_date}.csv"

    write_csv(
        suppliers_path,
        suppliers,
        [
            "supplier_id",
            "supplier_name",
            "country_code",
            "supplier_status",
        ],
    )

    write_csv(
        products_path,
        products,
        [
            "product_id",
            "sku",
            "product_name",
            "category",
            "supplier_id",
            "unit_cost",
            "product_status",
        ],
    )

    write_csv(
        locations_path,
        locations,
        [
            "location_id",
            "location_name",
            "location_type",
            "region",
            "country_code",
            "location_status",
        ],
    )

    print("Generated master data files:")
    print(f"- {suppliers_path.relative_to(PROJECT_ROOT)} ({len(suppliers)} rows)")
    print(f"- {products_path.relative_to(PROJECT_ROOT)} ({len(products)} rows)")
    print(f"- {locations_path.relative_to(PROJECT_ROOT)} ({len(locations)} rows)")
    print()
    print("Intentional bad records included:", include_bad_records)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate ERP-style master data CSV files for the integration platform."
    )

    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducible synthetic data.",
    )

    parser.add_argument("--suppliers", type=int, default=25)
    parser.add_argument("--products", type=int, default=250)
    parser.add_argument("--locations", type=int, default=50)
    parser.add_argument(
        "--no-bad-records",
        action="store_true",
        help="Generate only valid records.",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    random.seed(args.seed)

    generate_files(
        supplier_count=args.suppliers,
        product_count=args.products,
        location_count=args.locations,
        include_bad_records=not args.no_bad_records,
    )


if __name__ == "__main__":
    main()