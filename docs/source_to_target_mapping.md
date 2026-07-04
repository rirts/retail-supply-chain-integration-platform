# Source-to-Target Mapping

## Overview

This document describes how source records are mapped from inbound systems into the PostgreSQL integration platform.

The project follows a layered integration pattern:

```text
source system → raw → staging → target → monitoring
```

Each integration flow preserves raw data, validates records in staging, loads accepted records into target tables, stores rejected records with reasons, and reconciles source counts against target loads.

## Schemas

| Layer | Schema | Purpose |
|---|---|---|
| Source landing | `raw` | Stores incoming records from files, APIs, events, and NiFi demos |
| Validation | `staging` | Stores parsed records with validation status |
| Business-ready | `target` | Stores integrated dimensions and fact tables |
| Observability | `monitoring` | Stores audit logs, rejected records, validation results, and reconciliation results |

---

# Flat-File Master Data Mapping

## Suppliers

### Source

```text
data/inbound/suppliers/suppliers_YYYYMMDD.csv
```

### Raw Table

```text
raw.file_ingestion_raw
```

### Staging Table

```text
staging.stg_suppliers
```

### Target Table

```text
target.dim_supplier
```

| Source Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `supplier_id` | JSON payload | `supplier_id` | `supplier_id` | Required, unique |
| `supplier_name` | JSON payload | `supplier_name` | `supplier_name` | Required |
| `supplier_type` | JSON payload | `supplier_type` | `supplier_type` | Must be valid supplier type |
| `country` | JSON payload | `country` | `country` | Required |
| `status` | JSON payload | `supplier_status` | `supplier_status` | Must be valid status |
| source file name | metadata | `source_file_name` | n/a | Used for auditability |
| batch id | metadata | `batch_id` | n/a | Used for traceability |

---

## Products

### Source

```text
data/inbound/products/products_YYYYMMDD.csv
```

### Raw Table

```text
raw.file_ingestion_raw
```

### Staging Table

```text
staging.stg_products
```

### Target Table

```text
target.dim_product
```

| Source Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `product_id` | JSON payload | `product_id` | `product_id` | Required, unique |
| `sku` | JSON payload | `sku` | `sku` | Required |
| `product_name` | JSON payload | `product_name` | `product_name` | Required |
| `category` | JSON payload | `category` | `category` | Required |
| `supplier_id` | JSON payload | `supplier_id` | `supplier_id` | Must reference accepted supplier |
| `unit_cost` | JSON payload | `unit_cost` | `unit_cost` | Must be numeric and non-negative |
| `product_status` | JSON payload | `product_status` | `product_status` | Must be valid product status |
| source file name | metadata | `source_file_name` | n/a | Used for auditability |
| batch id | metadata | `batch_id` | n/a | Used for traceability |

---

## Locations

### Source

```text
data/inbound/locations/locations_YYYYMMDD.csv
```

### Raw Table

```text
raw.file_ingestion_raw
```

### Staging Table

```text
staging.stg_locations
```

### Target Table

```text
target.dim_location
```

| Source Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `location_id` | JSON payload | `location_id` | `location_id` | Required, unique |
| `location_name` | JSON payload | `location_name` | `location_name` | Required |
| `location_type` | JSON payload | `location_type` | `location_type` | Must be valid location type |
| `region` | JSON payload | `region` | `region` | Required |
| `country` | JSON payload | `country` | `country` | Required |
| `status` | JSON payload | `location_status` | `location_status` | Must be valid status |
| source file name | metadata | `source_file_name` | n/a | Used for auditability |
| batch id | metadata | `batch_id` | n/a | Used for traceability |

---

# API Integration Mapping

## Sales Orders

### Source

```text
GET /api/v1/sales-orders
```

### Raw Table

```text
raw.api_ingestion_raw
```

### Staging Table

```text
staging.stg_sales_orders
```

### Target Table

```text
target.fact_sales_order
```

| API Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `sales_order_id` | JSON payload | `sales_order_id` | `sales_order_id` | Required |
| `sales_order_line_id` | JSON payload | `sales_order_line_id` | `sales_order_line_id` | Required, unique line grain |
| `product_id` | JSON payload | `product_id` | `product_id` | Must reference `target.dim_product` |
| `location_id` | JSON payload | `location_id` | `location_id` | Must reference `target.dim_location` |
| `customer_channel` | JSON payload | `customer_channel` | `customer_channel` | Must be valid channel |
| `order_status` | JSON payload | `order_status` | `order_status` | Must be valid order status |
| `order_date` | JSON payload | `order_date` | `order_date` | Must cast to date |
| `requested_ship_date` | JSON payload | `requested_ship_date` | `requested_ship_date` | Must cast to date |
| `quantity_ordered` | JSON payload | `quantity_ordered` | `quantity_ordered` | Must be greater than zero |
| `unit_price` | JSON payload | `unit_price` | `unit_price` | Must be numeric and non-negative |
| `updated_at` | JSON payload | `updated_at` | `source_updated_at` | Used for incremental integration |

---

## Purchase Orders

### Source

```text
GET /api/v1/purchase-orders
```

### Raw Table

```text
raw.api_ingestion_raw
```

### Staging Table

```text
staging.stg_purchase_orders
```

### Target Table

```text
target.fact_purchase_order
```

| API Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `purchase_order_id` | JSON payload | `purchase_order_id` | `purchase_order_id` | Required |
| `purchase_order_line_id` | JSON payload | `purchase_order_line_id` | `purchase_order_line_id` | Required, unique line grain |
| `product_id` | JSON payload | `product_id` | `product_id` | Must reference `target.dim_product` |
| `supplier_id` | JSON payload | `supplier_id` | `supplier_id` | Must reference `target.dim_supplier` |
| `destination_location_id` | JSON payload | `destination_location_id` | `destination_location_id` | Must reference `target.dim_location` |
| `order_status` | JSON payload | `order_status` | `order_status` | Must be valid order status |
| `order_date` | JSON payload | `order_date` | `order_date` | Must cast to date |
| `expected_delivery_date` | JSON payload | `expected_delivery_date` | `expected_delivery_date` | Cannot be before order date |
| `quantity_ordered` | JSON payload | `quantity_ordered` | `quantity_ordered` | Must be greater than zero |
| `unit_cost` | JSON payload | `unit_cost` | `unit_cost` | Must be numeric and non-negative |
| `updated_at` | JSON payload | `updated_at` | `source_updated_at` | Used for incremental integration |

---

## Shipments

### Source

```text
GET /api/v1/shipments
```

### Raw Table

```text
raw.api_ingestion_raw
```

### Staging Table

```text
staging.stg_shipments
```

### Target Table

```text
target.fact_shipment
```

| API Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `shipment_id` | JSON payload | `shipment_id` | `shipment_id` | Required, unique |
| `related_order_type` | JSON payload | `related_order_type` | `related_order_type` | Must be valid related order type |
| `related_order_id` | JSON payload | `related_order_id` | `related_order_id` | Must align with related order type |
| `product_id` | JSON payload | `product_id` | `product_id` | Must reference `target.dim_product` |
| `origin_location_id` | JSON payload | `origin_location_id` | `origin_location_id` | Must reference `target.dim_location` |
| `destination_location_id` | JSON payload | `destination_location_id` | `destination_location_id` | Must reference `target.dim_location` |
| `shipment_status` | JSON payload | `shipment_status` | `shipment_status` | Must be valid shipment status |
| `shipped_date` | JSON payload | `shipped_date` | `shipped_date` | Must cast to date when present |
| `delivered_date` | JSON payload | `delivered_date` | `delivered_date` | Cannot be before shipped date |
| `quantity_shipped` | JSON payload | `quantity_shipped` | `quantity_shipped` | Must be greater than zero |
| `updated_at` | JSON payload | `updated_at` | `source_updated_at` | Used for incremental integration |

---

# Event Stream Mapping

## Inventory Events

### Source

```text
Redpanda topic: inventory-events
```

### Raw Table

```text
raw.inventory_events_raw
```

### Staging Table

```text
staging.stg_inventory_events
```

### Target Tables

```text
target.fact_inventory_movement
target.fact_inventory_snapshot
```

| Event Field | Raw Payload | Staging Field | Target Field | Transformation / Rule |
|---|---|---|---|---|
| `event_id` | JSON payload | `event_id` | `event_id` | Required, unique, idempotency key |
| `event_type` | JSON payload | `event_type` | `event_type` | Must be valid event type |
| `product_id` | JSON payload | `product_id` | `product_id` | Must reference `target.dim_product` |
| `location_id` | JSON payload | `location_id` | `location_id` | Must reference `target.dim_location` |
| `quantity_change` | JSON payload | `quantity_change` | `quantity_change` | Must be non-zero |
| `reason_code` | JSON payload | `reason_code` | `reason_code` | Must be valid reason code |
| `event_timestamp` | JSON payload | `event_timestamp` | `event_timestamp` | Required timestamp |
| `published_at` | JSON payload | `published_at` | `published_at` | Must be >= event timestamp |

## Inventory Snapshot Logic

Accepted inventory events are inserted into:

```text
target.fact_inventory_movement
```

Then the latest inventory state is aggregated into:

```text
target.fact_inventory_snapshot
```

Snapshot grain:

```text
product_id + location_id
```

This means the number of snapshot rows can be lower than the number of movement rows because multiple events can affect the same product-location combination.

---

# NiFi Demo Mapping

## NiFi Flat-File Demo

| Processor | Source | Target |
|---|---|---|
| `GetFile` | `products_nifi_demo.csv` | FlowFile |
| `CSVReader` | FlowFile content | Parsed records |
| `PutDatabaseRecord` | Parsed records | `raw.nifi_products_file_raw` |

Target table:

```text
raw.nifi_products_file_raw
```

This demo proves NiFi can land CSV records into PostgreSQL through JDBC.

## NiFi API Demo

| Processor | Source | Target |
|---|---|---|
| `InvokeHTTP` | Mock API endpoint | API response FlowFile |
| `SplitJson` | `$.data[*]` | Individual sales order records |
| `JsonTreeReader` | JSON records | Parsed records |
| `PutDatabaseRecord` | Parsed records | `raw.nifi_sales_orders_api_raw` |

Target table:

```text
raw.nifi_sales_orders_api_raw
```

This demo proves NiFi can call an API, split JSON payloads, and write records into PostgreSQL.

---

# Monitoring Outputs

Every production-style integration flow writes operational metadata.

| Output | Table | Purpose |
|---|---|---|
| Batch audit | `monitoring.batch_audit_log` | Tracks status and counts per batch |
| Rejected records | `monitoring.rejected_records` | Stores invalid records with rejection reasons |
| Validation results | `monitoring.validation_results` | Stores validation summaries |
| Reconciliation results | `monitoring.reconciliation_results` | Confirms source-to-target count consistency |

## Reconciliation Rules

```text
source_count = accepted_count + rejected_count
accepted_count = loaded_count
```

A batch can be successful even with rejected records when the rejected records are expected, captured, and reconciled.

Successful status with rejected records:

```text
MATCHED_WITH_REJECTIONS
```