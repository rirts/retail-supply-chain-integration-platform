create table if not exists raw.file_ingestion_raw (
    raw_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    source_system text not null,
    entity_name text not null,
    source_file_name text,
    row_number integer,
    raw_payload jsonb not null,
    ingested_at timestamptz not null default now()
);

create index if not exists idx_file_ingestion_raw_batch_id
    on raw.file_ingestion_raw(batch_id);

create index if not exists idx_file_ingestion_raw_entity_name
    on raw.file_ingestion_raw(entity_name);

create table if not exists raw.api_ingestion_raw (
    raw_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    source_system text not null,
    entity_name text not null,
    endpoint text not null,
    request_params jsonb,
    raw_payload jsonb not null,
    ingested_at timestamptz not null default now()
);

create index if not exists idx_api_ingestion_raw_batch_id
    on raw.api_ingestion_raw(batch_id);

create index if not exists idx_api_ingestion_raw_entity_name
    on raw.api_ingestion_raw(entity_name);

create table if not exists raw.inventory_events_raw (
    raw_event_id uuid primary key default gen_random_uuid(),
    event_id text,
    batch_id uuid,
    topic_name text not null default 'inventory-events',
    source_system text not null default 'warehouse_event_stream',
    raw_payload jsonb not null,
    consumed_at timestamptz not null default now()
);

create unique index if not exists idx_inventory_events_raw_event_id
    on raw.inventory_events_raw(event_id)
    where event_id is not null;