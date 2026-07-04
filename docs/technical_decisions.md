# Technical Decisions

## Overview

This document explains the main technical decisions behind the Retail Supply Chain Integration Platform.

The goal of the project is to demonstrate realistic Data Integration Engineering patterns, not just basic ETL scripting.

The platform was designed to show:

- multi-source integration
- raw data preservation
- deterministic validation
- rejected record handling
- source-to-target reconciliation
- middleware orchestration
- event-based ingestion
- operational troubleshooting

---

# Decision 1: Use PostgreSQL as the Integration Database

## Decision

Use PostgreSQL 16 as the central integration database.

## Reason

PostgreSQL provides enough capability to demonstrate enterprise integration patterns locally:

- schemas
- relational constraints
- JSONB raw payload storage
- SQL validation
- PLpgSQL procedures
- upserts
- audit tables
- reconciliation queries

## Alternatives Considered

| Alternative | Reason Not Used |
|---|---|
| Snowflake | Strong warehouse choice, but harder to run locally for a portfolio project |
| BigQuery | Good cloud warehouse, but would require cloud setup and credentials |
| SQL Server | Enterprise-relevant, but PostgreSQL is simpler for Docker-based reproducibility |
| DuckDB | Great for analytics, but less representative for integration/audit workflows |

## Outcome

PostgreSQL gives the project a realistic but reproducible local database layer.

---

# Decision 2: Separate Raw, Staging, Target, and Monitoring Schemas

## Decision

Use four main schemas:

```text
raw
staging
target
monitoring
```

## Reason

This mirrors common enterprise integration patterns.

| Schema | Purpose |
|---|---|
| `raw` | Preserve source records close to original form |
| `staging` | Parse, validate, and classify records |
| `target` | Store integrated business-ready tables |
| `monitoring` | Track audit logs, rejected records, validation results, and reconciliation |

## Benefit

This separation makes the data lifecycle clear:

```text
source → raw → staging → target → monitoring
```

It also makes troubleshooting easier because each layer has a clear responsibility.

---

# Decision 3: Preserve Raw Source Payloads

## Decision

Store raw source records before applying validation or transformation.

## Reason

In real integrations, raw data preservation is important for:

- auditability
- debugging
- replaying batches
- investigating source system issues
- proving why a record was rejected

## Outcome

Bad records are not silently discarded. They are preserved and linked to rejected record metadata.

---

# Decision 4: Store Rejected Records Instead of Silently Cleaning Them

## Decision

Invalid records are inserted into:

```text
monitoring.rejected_records
```

with explicit rejection reasons.

## Reason

A professional integration pipeline should not hide source data problems.

Rejected records help answer:

- Which record failed?
- Which source sent it?
- Which validation rule failed?
- Was the failure expected?
- Does the source team need to resend corrected data?

## Outcome

The project demonstrates controlled failure handling instead of silent data loss.

---

# Decision 5: Use SQL/PLpgSQL for Validation and Reconciliation

## Decision

Use SQL and PLpgSQL functions for deterministic validation, target loading, and reconciliation.

## Reason

Many integration platforms rely heavily on SQL for validation and business rules because SQL is:

- deterministic
- transparent
- auditable
- close to the data
- easy to inspect and test through queries

## Examples

SQL handles:

- required-field validation
- type casting checks
- duplicate detection
- referential integrity checks
- accepted/rejected classification
- upserts into target tables
- source-to-target reconciliation

## Outcome

The project shows more than Python scripting. It demonstrates database-centered integration engineering.

---

# Decision 6: Use Python for Source Simulation and Load Orchestration

## Decision

Use Python scripts for:

- synthetic data generation
- flat-file raw loading
- API extraction
- event production
- event consumption
- invoking SQL validation/load functions

## Reason

Python is a practical choice for integration automation because it can work with:

- files
- APIs
- databases
- Kafka-compatible brokers
- local development workflows

## Outcome

Python acts as the operational runner while SQL enforces validation and reconciliation logic.

---

# Decision 7: Use FastAPI as a Mock Enterprise API

## Decision

Build a local FastAPI service to simulate enterprise API endpoints.

## Reason

A real Data Integration Engineer often works with operational APIs. The project needed an API source that supports realistic patterns without relying on external services.

The mock API supports:

- sales orders
- purchase orders
- shipments
- pagination
- `updated_since`
- intentionally bad records

## Outcome

The API flow demonstrates ingestion from operational systems, not just CSV loading.

---

# Decision 8: Use Redpanda for Event Streaming

## Decision

Use Redpanda as a Kafka-compatible event broker.

## Reason

Redpanda is lightweight and easy to run locally with Docker while still demonstrating Kafka-style event integration.

The event flow demonstrates:

- topic creation
- event production
- event consumption
- duplicate event handling
- idempotent ingestion
- event validation
- inventory movement and snapshot tables

## Outcome

The project covers event-based integration, which is important for modern supply chain and inventory systems.

---

# Decision 9: Use `event_id` for Event Idempotency

## Decision

Use `event_id` as the idempotency key for inventory events.

## Reason

Event streams may deliver duplicate messages. A robust event integration should avoid double-counting inventory movements.

## Outcome

Duplicate event IDs are ignored during raw ingestion and written to rejected records with:

```text
EVENT_DEDUPLICATION
```

This demonstrates both data protection and operational traceability.

---

# Decision 10: Use Apache NiFi as Middleware Demonstration

## Decision

Use Apache NiFi for visual middleware demos, not as the only processing engine.

## Reason

NiFi is strong for:

- visual orchestration
- file pickup
- API calls
- routing
- JDBC writes
- middleware-style data movement

However, the project already has strong SQL validation, rejected records, and reconciliation logic. Rebuilding every rule visually in NiFi would make the project harder to maintain and less clear.

## NiFi Demos Implemented

| Demo | Processors |
|---|---|
| PostgreSQL connectivity | `GenerateFlowFile → PutSQL` |
| Flat-file ingestion | `GetFile → PutDatabaseRecord` |
| API ingestion | `InvokeHTTP → SplitJson → PutDatabaseRecord` |

## Outcome

NiFi proves middleware integration capability without making the project unnecessarily complex.

---

# Decision 11: Include Intentionally Bad Records

## Decision

Generate synthetic data with controlled invalid records.

## Reason

A clean-only dataset does not prove integration quality. Real source systems send bad data.

The project intentionally includes:

- duplicate IDs
- missing required fields
- invalid enum values
- invalid references
- negative amounts
- invalid quantities
- invalid event types
- duplicate event IDs

## Outcome

The project can demonstrate validation, rejection handling, and reconciliation in a realistic way.

---

# Decision 12: Reconcile Every Production-Style Batch

## Decision

After target loading, every production-style batch writes reconciliation results.

## Reconciliation Rules

```text
source_count = accepted_count + rejected_count
accepted_count = loaded_count
```

## Reason

Integration work is not complete when data is inserted. It must be proven that the expected records arrived in the expected target tables.

## Outcome

A batch with rejected records can still be successful when:

```text
status = MATCHED_WITH_REJECTIONS
```

This means valid data loaded correctly and invalid data was handled in a controlled way.

---

# Decision 13: Use Docker Compose for Reproducibility

## Decision

Run infrastructure locally using Docker Compose.

## Reason

The project needs to be reproducible without manual installation of PostgreSQL, NiFi, Redpanda, or FastAPI.

## Outcome

The main services can be started with:

```powershell
docker compose --profile middleware --profile eventing up -d --build
```

This makes the project easier to review and run.

---

# Decision 14: Keep the Project Focused

## Decision

Stop adding major new flows after covering:

- flat files
- APIs
- event streams
- NiFi middleware
- audit logs
- rejected records
- reconciliation
- troubleshooting documentation

## Reason

A portfolio project should be deep enough to show skill, but focused enough to explain clearly.

Adding more tools or flows would increase complexity without adding much hiring value.

## Outcome

The project is broad enough to demonstrate integration engineering and focused enough to be explainable in interviews.