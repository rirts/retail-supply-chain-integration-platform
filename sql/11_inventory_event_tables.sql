create table if not exists staging.stg_inventory_events (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    event_id text not null,
    event_type text,
    product_id text,
    location_id text,
    quantity_change integer,
    reason_code text,
    event_timestamp timestamptz,
    published_at timestamptz,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists target.fact_inventory_movement (
    event_id text primary key,
    event_type text not null,
    product_id text not null references target.dim_product(product_id),
    location_id text not null references target.dim_location(location_id),
    quantity_change integer not null,
    reason_code text not null,
    event_timestamp timestamptz not null,
    published_at timestamptz not null,
    source_system text not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);

create table if not exists target.fact_inventory_snapshot (
    product_id text not null references target.dim_product(product_id),
    location_id text not null references target.dim_location(location_id),
    on_hand_quantity integer not null default 0,
    last_event_timestamp timestamptz not null,
    last_updated_at timestamptz not null default now(),
    primary key (product_id, location_id)
);