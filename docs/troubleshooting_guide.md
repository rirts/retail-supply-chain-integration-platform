# Troubleshooting Guide

## Overview

This guide documents common issues and fixes for the Retail Supply Chain Integration Platform.

The project uses Docker Compose, PostgreSQL, Apache NiFi, FastAPI, Redpanda, and Python scripts. Most issues fall into one of these categories:

- Docker service startup
- PostgreSQL connectivity
- NiFi configuration
- API availability
- Redpanda topic or consumer issues
- duplicate loads during demos
- missing or stale local data files

---

# Docker Issues

## Services are not running

### Symptom

```powershell
docker compose ps
```

shows one or more services as stopped or unhealthy.

### Fix

Restart all services:

```powershell
docker compose --profile middleware --profile eventing down
docker compose --profile middleware --profile eventing up -d --build
```

Check logs for a specific service:

```powershell
docker logs rscp_postgres
docker logs rscp_mock_api
docker logs rscp_nifi
docker logs rscp_redpanda
```

---

# PostgreSQL Issues

## Cannot connect to PostgreSQL from host

### Symptom

Python scripts fail with connection errors.

### Expected host connection

```text
Host: localhost
Port: 5432
Database: integration_platform
User: integration_user
Password: integration_password
```

### Fix

Check the container:

```powershell
docker compose ps postgres
```

Test connection:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "select 1;"
```

## Cannot connect to PostgreSQL from NiFi

### Symptom

NiFi `DBCPConnectionPool` fails validation.

### Expected Docker-network connection

```text
Host: postgres
Port: 5432
Database: integration_platform
```

### Correct JDBC URL

```text
jdbc:postgresql://postgres:5432/integration_platform
```

Do not use `localhost` inside NiFi. Inside the Docker network, `localhost` refers to the NiFi container itself.

---

# NiFi Issues

## NiFi page does not load immediately

### Symptom

Browser shows connection error for:

```text
https://localhost:8443/nifi
```

### Cause

NiFi can take several minutes to start.

### Fix

Check logs:

```powershell
docker logs rscp_nifi
```

Wait until startup completes, then reload the browser.

## Cannot log in to NiFi

### Expected URL

```text
https://localhost:8443/nifi
```

### Default local credentials

```text
Username: admin
Password: ChangeMe_IntegrationLab_2026!
```

If credentials were changed, check:

```powershell
Get-Content .env
```

Look for:

```text
NIFI_USERNAME
NIFI_PASSWORD
```

## NiFi DBCPConnectionPool cannot find PostgreSQL driver

### Symptom

NiFi controller service fails because the PostgreSQL JDBC driver is missing.

### Fix

Verify the driver exists locally:

```powershell
Get-ChildItem nifi/drivers
```

Expected file:

```text
postgresql-42.7.12.jar
```

Expected NiFi driver location:

```text
/opt/nifi/nifi-current/drivers/postgresql-42.7.12.jar
```

Restart NiFi after adding the driver:

```powershell
docker compose --profile middleware restart nifi
```

## PutDatabaseRecord says table was not found

### Symptom

NiFi error:

```text
Table raw.some_table not found
```

### Cause

NiFi may treat `raw.some_table` as a literal table name instead of schema + table.

### Fix

Use separate schema and table properties:

```text
Schema Name: raw
Table Name: some_table
```

Do not put `raw.` in the `Table Name` field when a separate schema field exists.

## NiFi flat-file demo loads duplicate rows

### Symptom

Expected 255 rows but got 510, 765, or more.

### Cause

`GetFile` read the same file multiple times.

### Fix

Stop `GetFile`.

Then truncate the table:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_products_file_raw;"
```

Set:

```text
Keep Source File: false
```

Copy the demo file again:

```powershell
Copy-Item data/inbound/products/products_*.csv data/nifi_demo/inbound/products/products_nifi_demo.csv -Force
```

Run `GetFile` once and stop it after processing.

## NiFi API demo loads more than 25 rows

### Symptom

Expected 25 rows but got 50 or more.

### Cause

`InvokeHTTP` ran more than once.

### Fix

Truncate the table:

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_sales_orders_api_raw;"
```

Set `InvokeHTTP` run schedule to a long interval:

```text
Run Schedule: 999 sec
```

Start it once, wait for processing, then stop `InvokeHTTP`.

---

# FastAPI Issues

## API health check fails

### Symptom

```powershell
Invoke-RestMethod http://localhost:8000/health
```

fails.

### Fix

Check service status:

```powershell
docker compose ps mock-api
```

Check logs:

```powershell
docker logs rscp_mock_api
```

Rebuild the API container:

```powershell
docker compose --profile middleware --profile eventing up -d --build mock-api
```

## NiFi cannot call API using localhost

### Symptom

`InvokeHTTP` fails when using:

```text
http://localhost:8000
```

### Cause

Inside NiFi, `localhost` means the NiFi container, not the host machine.

### Fix

Use the Docker service name:

```text
http://mock-api:8000/api/v1/sales-orders?limit=25&include_bad_records=true
```

---

# Redpanda Issues

## Topic does not exist

### Symptom

Producer or consumer fails because `inventory-events` does not exist.

### Fix

Create the topic:

```powershell
docker exec -it rscp_redpanda rpk topic create inventory-events --brokers localhost:9092
```

List topics:

```powershell
docker exec -it rscp_redpanda rpk topic list --brokers localhost:9092
```

## Topic already exists

### Symptom

Topic creation command returns an error because the topic already exists.

### Fix

No action needed. Continue with producer/consumer scripts.

## Consumer reads zero messages

### Possible causes

- Producer was not run.
- Consumer group already consumed the messages.
- Topic is empty.
- Wrong bootstrap server.
- Wrong topic name.

### Fix

Produce events again:

```powershell
python scripts/produce_inventory_events.py --count 200 --seed 42
```

Then consume:

```powershell
python scripts/consume_inventory_events_to_raw.py --max-messages 206
```

## Duplicate inventory event detected

### Symptom

One duplicate event is ignored during raw ingestion.

### Expected behavior

The demo intentionally produces a duplicate event ID.

Expected outcome:

```text
duplicates_ignored = 1
```

The duplicate should be written to:

```text
monitoring.rejected_records
```

with rejection stage:

```text
EVENT_DEDUPLICATION
```

This is correct and demonstrates idempotency.

---

# Python Script Issues

## Virtual environment is not active

### Symptom

Python cannot find dependencies such as `psycopg`, `requests`, or `confluent_kafka`.

### Fix

Activate the virtual environment:

```powershell
.\.venv\Scripts\Activate.ps1
```

Install requirements:

```powershell
python -m pip install -r requirements.txt
```

## PowerShell cannot run activation script

### Symptom

PowerShell blocks the virtual environment activation script.

### Fix

Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

## Generated CSV files are missing

### Symptom

Flat-file loader cannot find files under:

```text
data/inbound
```

### Fix

Regenerate data:

```powershell
python scripts/generate_master_data_files.py --seed 42
```

Verify:

```powershell
Get-ChildItem data/inbound -Recurse
```

---

# Data Quality / Reconciliation Issues

## Batch completed with rejected records

### Symptom

Batch status is:

```text
COMPLETED_WITH_REJECTIONS
```

### Meaning

This is expected when the source includes intentionally bad records.

The batch is successful if reconciliation passes.

Check:

```sql
select
    entity_name,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status
from monitoring.reconciliation_results
order by reconciled_at;
```

Successful status:

```text
MATCHED_WITH_REJECTIONS
```

## Reconciliation failed

### Symptom

Status:

```text
RECONCILIATION_FAILED
```

### Meaning

Accepted records did not match loaded records.

### Investigation queries

Check audit log:

```sql
select *
from monitoring.batch_audit_log
order by created_at desc;
```

Check reconciliation:

```sql
select *
from monitoring.reconciliation_results
order by reconciled_at desc;
```

Check rejected records:

```sql
select
    entity_name,
    rejection_stage,
    rejection_reason,
    count(*)
from monitoring.rejected_records
group by 1, 2, 3
order by 1, 4 desc;
```

## API records rejected due to missing products or locations

### Cause

API source records reference product or location IDs that are not loaded into target dimensions.

### Fix

Run flat-file master data integration first:

```powershell
python scripts/load_master_data_to_raw.py
python scripts/validate_master_data_batches.py
python scripts/load_master_data_targets.py
```

Then rerun API integration:

```powershell
python scripts/load_api_data_to_raw.py
python scripts/validate_api_batches.py
python scripts/load_api_targets.py
```

## Event records rejected due to missing products or locations

### Cause

Inventory events reference product/location IDs not available in target dimensions.

### Fix

Run master data first, then event integration.

---

# Reset Procedures

## Reset only NiFi demo tables

```powershell
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_products_file_raw;"
docker exec -it rscp_postgres psql -U integration_user -d integration_platform -c "truncate table raw.nifi_sales_orders_api_raw;"
```

## Reset all containers but keep volumes

```powershell
docker compose --profile middleware --profile eventing down
docker compose --profile middleware --profile eventing up -d --build
```

## Full reset including volumes

```powershell
docker compose --profile middleware --profile eventing down -v
docker compose --profile middleware --profile eventing up -d --build
```

Warning: this removes PostgreSQL data and NiFi state.

---

# General Debugging Checklist

When something fails, check in this order:

1. Are Docker services running?
2. Is PostgreSQL reachable?
3. Are source files generated?
4. Is the mock API healthy?
5. Does the Redpanda topic exist?
6. Is the correct host being used from the correct context?
   - Host machine uses `localhost`
   - Docker containers use service names like `postgres` or `mock-api`
7. Did the batch create an audit log record?
8. Were records rejected intentionally?
9. Did reconciliation pass?
10. Are duplicate demo loads caused by running a processor or script more than once?