create table if not exists staging.stg_suppliers (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    supplier_id text not null,
    supplier_name text,
    country_code text,
    supplier_status text,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists staging.stg_products (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    product_id text not null,
    sku text,
    product_name text,
    category text,
    supplier_id text,
    unit_cost numeric(18, 4),
    product_status text,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists staging.stg_locations (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    location_id text not null,
    location_name text,
    location_type text,
    region text,
    country_code text,
    location_status text,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);