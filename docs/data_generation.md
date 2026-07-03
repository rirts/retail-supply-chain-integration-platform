# Data Generation

This project uses synthetic supply chain data to simulate enterprise data integration scenarios for a retail planning platform.

## Generated Master Data Files

The first integration flow uses ERP-style flat files:

| Entity | Folder | Description |
|---|---|---|
| Suppliers | `data/inbound/suppliers/` | Supplier master data |
| Products | `data/inbound/products/` | Product/SKU master data |
| Locations | `data/inbound/locations/` | Store, DC, and warehouse master data |

## Intentional Bad Records

The generator includes intentional data quality issues to demonstrate validation, rejected record handling, audit logging, and reconciliation.

Examples:

| Entity | Error Type |
|---|---|
| Suppliers | Duplicate supplier ID |
| Suppliers | Missing supplier name |
| Suppliers | Invalid country code |
| Suppliers | Invalid supplier status |
| Products | Duplicate product ID |
| Products | Missing SKU |
| Products | Unknown supplier reference |
| Products | Negative unit cost |
| Products | Invalid product status |
| Locations | Duplicate location ID |
| Locations | Invalid location type |
| Locations | Missing country code |
| Locations | Invalid location status |

## Generate Files

```powershell
python scripts/generate_master_data_files.py
```

## Generate Only Valid Files

```powershell
python scripts/generate_master_data_files.py --no-bad-records
```

## Reproducible Data Generation

By default, the generator uses seed `42` to keep demo data reproducible.

```powershell
python scripts/generate_master_data_files.py --seed 42
```

## Notes

Generated CSV files are intentionally excluded from Git through `.gitignore`.

The repository stores the generator script and documentation, not the generated output files. This keeps the project clean and reproducible.

To regenerate the demo files at any time, run:

```powershell
python scripts/generate_master_data_files.py
```