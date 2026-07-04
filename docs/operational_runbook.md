# Operational Runbook

## Overview

This runbook describes how to operate the Retail Supply Chain Integration Platform locally.

It covers:

- starting services
- validating infrastructure
- running integration flows
- checking audit logs
- checking rejected records
- checking reconciliation results
- stopping and resetting the environment

## Prerequisites

Required tools:

- Docker Desktop
- Python 3.12+
- PowerShell
- Git

Recommended:

- Windows 11
- WSL2 Docker backend

## Environment Setup

### 1. Create Python virtual environment

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

### 2. Create local environment file

```powershell
Copy-Item .env.example .env
```

### 3. Start all services

```powershell
docker compose --profile middleware --profile eventing up -d --build
```

### 4. Validate services

```powershell
docker compose ps
```

Expected services:

| Service | Purpose |
|---|---|
| `rscp_postgres` | PostgreSQL integration database |
| `rscp_adminer` | PostgreSQL UI |
| `rscp_mock_api` | Mock enterprise REST API |
| `rscp_nifi` | Apache NiFi middleware |
| `rscp_redpanda` | Kafka-compatible event broker |
| `rscp_redpanda_console` | Event topic inspection UI |

## Useful URLs

| Service | URL |
|---|---|
| FastAPI docs | `http://localhost:8000/docs` |
| Adminer | `http://localhost:8082` |
| NiFi | `https://localhost:8443/nifi` |
| Redpanda Console | `http://localhost:8081` |

## Database Connection

From host machine:

```text
Host: localhost
Port: 5432
Database: integration_platform
User: integration_user
Password: integration_password
```

From Docker containers:

```text
Host: postgres
Port: 5432
Database: integration_platform
User: integration_user
Password: integration_password
```

## Full Demo Execution

### 1. Generate master data files

```powershell
python scripts/generate_master_data_files.py --seed 42
```

Expected output files:

```text
data/inbound/suppliers/suppliers_YYYYMMDD.csv
data/inbound/products/products_YYYYMMDD.csv
data/inbound/locations/locations_YYYYMMDD.csv
```

### 2. Run flat-file integration

```powershell
python scripts/load_master_data_to_raw.py
python scripts/validate_master_data_batches.py
python scripts/load_master_data_targets.py
```

This flow loads:

- suppliers
- products
- locations

Expected target tables:

```text
target.dim_supplier
target.dim_product
target.dim_location
```

### 3. Run API integration

```powershell
python scripts/load_api_data_to_raw.py
python scripts/validate_api_batches.py
python scripts/load_api_targets.py
```

This flow loads:

- sales orders
- purchase orders
- shipments

Expected target tables:

```text
target.fact_sales_order
target.fact_purchase_order
target.fact_shipment
```

### 4. Run event-stream integration

Create the Redpanda topic if needed:

```powershell
docker exec -it rscp_redpanda rpk topic create inventory-events --brokers localhost:9092
```

Produce inventory events:

```powershell
python scripts/produce_inventory_events.py --count 200 --seed 42
```

Consume inventory events:

```powershell
python scripts/consume_inventory_events_to_raw.py --max-messages 206
```

Validate and load events:

```powershell
python scripts/validate_inventory_event_batch.py
python scripts/load_inventory_targets.py
```

Expected target tables:

```text
target.fact_inventory_movement
target.fact_inventory_snapshot
```

## NiFi Operational Checks

### NiFi URL

```text
https://localhost:8443/nifi
```

### NiFi login

Credentials are configured in `.env`.

Default local credentials:

```text
Username: admin
Password: ChangeMe_IntegrationLab_2026!
```

### PostgreSQL JDBC driver

The PostgreSQL JDBC driver should exist in:

```text
nifi/drivers/postgresql-42.7.12.jar
```

Inside the NiFi container, the path is:

```text
/opt/nifi/nifi-current/drivers/postgresql-42.7.12.jar
```

### NiFi DBCPConnectionPool

Expected properties:

| Property | Value |
|---|---|
| Database Connection URL | `jdbc:postgresql://postgres:5432/integration_platform` |
| Driver Class Name | `org.postgresql.Driver` |
| Driver Location(s) | `/opt/nifi/nifi-current/drivers/postgresql-42.7.12.jar` |
| Database User | `integration_user` |
| Password | `integration_password` |
| Validation Query | `select 1` |

## NiFi Demo Flows

### PostgreSQL Connectivity Test

Flow:

```text
GenerateFlowFile → PutSQL → monitoring.nifi_connectivity_test
```

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select test_name, test_status, details, created_at from monitoring.nifi_connectivity_test order by created_at desc limit 5;"
```

### Flat-File Ingestion Demo

Flow:

```text
GetFile → PutDatabaseRecord → raw.nifi_products_file_raw
```

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select count(*) as nifi_loaded_products from raw.nifi_products_file_raw;"
```

Expected result:

```text
255
```

### API Ingestion Demo

Flow:

```text
InvokeHTTP → SplitJson → PutDatabaseRecord → raw.nifi_sales_orders_api_raw
```

Validation query:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select count(*) as nifi_loaded_sales_orders from raw.nifi_sales_orders_api_raw;"
```

Expected result:

```text
25
```

## Monitoring Queries

### Batch audit summary

```sql
select
    entity_name,
    batch_type,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    status,
    created_at,
    updated_at
from monitoring.batch_audit_log
order by created_at;
```

### Rejected records summary

```sql
select
    entity_name,
    rejection_stage,
    rejection_reason,
    count(*) as rejected_count
from monitoring.rejected_records
group by 1, 2, 3
order by entity_name, rejected_count desc;
```

### Reconciliation summary

```sql
select
    entity_name,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status,
    reconciled_at
from monitoring.reconciliation_results
order by reconciled_at;
```

### Target table counts

```sql
select 'dim_supplier' as table_name, count(*) from target.dim_supplier
union all
select 'dim_product', count(*) from target.dim_product
union all
select 'dim_location', count(*) from target.dim_location
union all
select 'fact_sales_order', count(*) from target.fact_sales_order
union all
select 'fact_purchase_order', count(*) from target.fact_purchase_order
union all
select 'fact_shipment', count(*) from target.fact_shipment
union all
select 'fact_inventory_movement', count(*) from target.fact_inventory_movement
union all
select 'fact_inventory_snapshot', count(*) from target.fact_inventory_snapshot;
```

## Expected Batch Behavior

A successful batch may have rejected records.

This is expected when the source intentionally includes bad records for validation testing.

Successful controlled status:

```text
COMPLETED_WITH_REJECTIONS
```

Successful reconciliation status:

```text
MATCHED_WITH_REJECTIONS
```

This means:

```text
source_count = accepted_count + rejected_count
accepted_count = loaded_count
```

## Stopping Services

```powershell
docker compose --profile middleware --profile eventing down
```

## Full Reset

Use this only when you want to remove containers and volumes.

```powershell
docker compose --profile middleware --profile eventing down -v
```

Then restart:

```powershell
docker compose --profile middleware --profile eventing up -d --build
```

After a full reset, rerun the SQL setup automatically mounted into PostgreSQL and rerun the data pipelines.

## Operational Notes

- Raw records are preserved for traceability.
- Rejected records are stored instead of silently discarded.
- Target loading only uses accepted records.
- Every production-style flow writes audit and reconciliation metadata.
- NiFi demos prove middleware ingestion patterns but do not replace the SQL-centered validation layer.