# Demo Walkthrough

## Overview

This walkthrough shows how to run the Retail Supply Chain Integration Platform demo from a local development environment.

The demo covers:

1. Infrastructure startup
2. Flat-file integration
3. API integration
4. Event-stream integration
5. Apache NiFi middleware demos
6. Monitoring and reconciliation checks

The expected results assume the default seed:

```text
--seed 42
```

---

# 1. Start the Platform

## Activate Python Environment

```powershell
.\.venv\Scripts\Activate.ps1
```

## Start Docker Services

```powershell
docker compose --profile middleware --profile eventing up -d --build
```

## Validate Services

```powershell
docker compose ps
```

Expected services:

```text
rscp_postgres
rscp_adminer
rscp_mock_api
rscp_nifi
rscp_redpanda
rscp_redpanda_console
```

## Validate PostgreSQL

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select 1;"
```

## Validate Mock API

```powershell
Invoke-RestMethod http://localhost:8000/health
```

---

# 2. Generate Source Data

```powershell
python scripts/generate_master_data_files.py --seed 42
```

Expected files:

```text
data/inbound/suppliers/suppliers_YYYYMMDD.csv
data/inbound/products/products_YYYYMMDD.csv
data/inbound/locations/locations_YYYYMMDD.csv
```

Check files:

```powershell
Get-ChildItem data/inbound -Recurse
```

---

# 3. Run Flat-File Integration

## Load Raw Files

```powershell
python scripts/load_master_data_to_raw.py
```

## Validate Master Data

```powershell
python scripts/validate_master_data_batches.py
```

## Load Target Dimensions

```powershell
python scripts/load_master_data_targets.py
```

## Validate Target Counts

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select 'dim_supplier' as table_name, count(*) from target.dim_supplier union all select 'dim_product', count(*) from target.dim_product union all select 'dim_location', count(*) from target.dim_location;"
```

Expected result with seed `42`:

| Table | Expected Count |
|---|---:|
| `target.dim_supplier` | 24 |
| `target.dim_product` | 233 |
| `target.dim_location` | 49 |

## Validate Flat-File Reconciliation

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select entity_name, source_count, accepted_count, rejected_count, loaded_count, count_difference, status from monitoring.reconciliation_results where entity_name in ('suppliers', 'products', 'locations') order by entity_name;"
```

Expected pattern:

```text
status = MATCHED_WITH_REJECTIONS
count_difference = 0
```

---

# 4. Run API Integration

## Load API Data to Raw

```powershell
python scripts/load_api_data_to_raw.py
```

## Validate API Batches

```powershell
python scripts/validate_api_batches.py
```

## Load API Target Tables

```powershell
python scripts/load_api_targets.py
```

## Validate API Target Counts

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select 'fact_sales_order' as table_name, count(*) from target.fact_sales_order union all select 'fact_purchase_order', count(*) from target.fact_purchase_order union all select 'fact_shipment', count(*) from target.fact_shipment;"
```

Expected result with seed `42`:

| Table | Expected Count |
|---|---:|
| `target.fact_sales_order` | 280 |
| `target.fact_purchase_order` | 136 |
| `target.fact_shipment` | 164 |

## Validate API Reconciliation

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select entity_name, source_count, accepted_count, rejected_count, loaded_count, count_difference, status from monitoring.reconciliation_results where entity_name in ('sales_orders', 'purchase_orders', 'shipments') order by entity_name;"
```

Expected pattern:

```text
status = MATCHED_WITH_REJECTIONS
count_difference = 0
```

---

# 5. Run Event-Stream Integration

## Create Redpanda Topic

```powershell
docker exec -it rscp_redpanda rpk topic create inventory-events --brokers localhost:9092
```

If the topic already exists, continue.

## Produce Inventory Events

```powershell
python scripts/produce_inventory_events.py --count 200 --seed 42
```

Expected behavior:

```text
206 total events produced
```

The demo includes valid events plus intentionally bad and duplicate events.

## Consume Inventory Events

```powershell
python scripts/consume_inventory_events_to_raw.py --max-messages 206
```

Expected behavior:

```text
raw_inserted = 205
duplicates_ignored = 1
```

## Validate Inventory Event Batch

```powershell
python scripts/validate_inventory_event_batch.py
```

Expected result:

```text
source_count = 206
accepted_count = 187
rejected_count = 19
```

## Load Inventory Targets

```powershell
python scripts/load_inventory_targets.py
```

Expected result:

```text
loaded_count = 187
status = MATCHED_WITH_REJECTIONS
```

## Validate Inventory Target Counts

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select 'fact_inventory_movement' as table_name, count(*) from target.fact_inventory_movement union all select 'fact_inventory_snapshot', count(*) from target.fact_inventory_snapshot;"
```

Expected result:

| Table | Expected Count |
|---|---:|
| `target.fact_inventory_movement` | 187 |
| `target.fact_inventory_snapshot` | 182 |

Note:

`fact_inventory_snapshot` has fewer rows than `fact_inventory_movement` because the snapshot is aggregated by:

```text
product_id + location_id
```

---

# 6. Run Apache NiFi Demos

## NiFi URL

```text
https://localhost:8443/nifi
```

## Default Local Login

```text
Username: admin
Password: ChangeMe_IntegrationLab_2026!
```

Credentials can be checked in:

```powershell
Get-Content .env
```

---

## 6.1 PostgreSQL Connectivity Demo

Flow:

```text
GenerateFlowFile → PutSQL → monitoring.nifi_connectivity_test
```

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select test_name, test_status, details, created_at from monitoring.nifi_connectivity_test order by created_at desc limit 5;"
```

Expected result:

```text
nifi_postgres_connectivity | PASSED
```

---

## 6.2 Flat-File NiFi Demo

Flow:

```text
GetFile → PutDatabaseRecord → raw.nifi_products_file_raw
```

Prepare demo file:

```powershell
New-Item -ItemType Directory -Force data/nifi_demo/inbound/products | Out-Null
Copy-Item data/inbound/products/products_*.csv data/nifi_demo/inbound/products/products_nifi_demo.csv -Force
```

Reset table:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_products_file_raw;"
```

Run the NiFi flow once.

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select count(*) as nifi_loaded_products from raw.nifi_products_file_raw;"
```

Expected result:

```text
255
```

---

## 6.3 API NiFi Demo

Flow:

```text
InvokeHTTP → SplitJson → PutDatabaseRecord → raw.nifi_sales_orders_api_raw
```

API URL from inside NiFi:

```text
http://mock-api:8000/api/v1/sales-orders?limit=25&include_bad_records=true
```

Reset table:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_sales_orders_api_raw;"
```

Run the NiFi flow once.

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select count(*) as nifi_loaded_sales_orders from raw.nifi_sales_orders_api_raw;"
```

Expected result:

```text
25
```

---

# 7. Review Monitoring Outputs

## Batch Audit Log

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select entity_name, batch_type, source_count, accepted_count, rejected_count, loaded_count, status from monitoring.batch_audit_log order by created_at;"
```

## Rejected Records by Reason

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select entity_name, rejection_stage, rejection_reason, count(*) as rejected_count from monitoring.rejected_records group by 1, 2, 3 order by entity_name, rejected_count desc;"
```

## Reconciliation Results

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select entity_name, source_count, accepted_count, rejected_count, loaded_count, count_difference, status from monitoring.reconciliation_results order by reconciled_at;"
```

Expected successful reconciliation statuses:

```text
MATCHED_WITH_REJECTIONS
```

This means:

```text
source_count = accepted_count + rejected_count
accepted_count = loaded_count
```

---

# 8. Run Demo Query File

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -f /docker-entrypoint-initdb.d/07_demo_queries.sql
```

This file includes useful review queries for:

- target counts
- rejected records
- reconciliation
- inventory movements
- inventory snapshot
- API facts
- NiFi demo tables

---

# 9. Stop the Platform

```powershell
docker compose --profile middleware --profile eventing down
```

---

# 10. Full Reset

Use this only when you want to remove containers and volumes.

```powershell
docker compose --profile middleware --profile eventing down -v
docker compose --profile middleware --profile eventing up -d --build
```

After a full reset, rerun the full demo from the beginning.

---

# Demo Summary

By the end of the walkthrough, the project demonstrates:

| Capability | Demonstrated By |
|---|---|
| Flat-file integration | CSV master data pipeline |
| API integration | FastAPI source pipeline |
| Event integration | Redpanda inventory events |
| Middleware | Apache NiFi demos |
| Data quality | SQL validation functions |
| Rejected records | `monitoring.rejected_records` |
| Audit logging | `monitoring.batch_audit_log` |
| Reconciliation | `monitoring.reconciliation_results` |
| Idempotency | Duplicate event handling |
| Operational support | Runbook and troubleshooting guide |