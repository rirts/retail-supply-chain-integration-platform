# API Integration

This project includes a mock enterprise REST API used to simulate operational supply chain systems.

## API Sources

| Endpoint | Description |
|---|---|
| `/api/v1/sales-orders` | Sales order line records |
| `/api/v1/purchase-orders` | Purchase order line records |
| `/api/v1/shipments` | Shipment records |

## Supported Query Parameters

| Parameter | Description |
|---|---|
| `updated_since` | Filters records by `updated_at` timestamp |
| `limit` | Page size |
| `offset` | Pagination offset |
| `include_bad_records` | Includes intentional bad records for validation testing |

## Example Requests

```powershell
Invoke-RestMethod "http://localhost:8000/api/v1/sales-orders?limit=5"
```

```powershell
Invoke-RestMethod "http://localhost:8000/api/v1/purchase-orders?limit=5"
```

```powershell
Invoke-RestMethod "http://localhost:8000/api/v1/shipments?limit=5"
```

## Intentional Bad Records

The API includes intentional data quality issues such as:

| Entity | Error Type |
|---|---|
| Sales Orders | Unknown product reference |
| Sales Orders | Invalid quantity |
| Sales Orders | Invalid order status |
| Purchase Orders | Unknown supplier reference |
| Purchase Orders | Expected delivery date before order date |
| Purchase Orders | Negative unit cost |
| Shipments | Delivered before shipped |
| Shipments | Unknown location reference |
| Shipments | Negative shipped quantity |

These records are used to demonstrate validation, rejected record handling, audit logging, and source-to-target reconciliation.