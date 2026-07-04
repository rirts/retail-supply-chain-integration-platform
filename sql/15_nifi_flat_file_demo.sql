create table if not exists raw.nifi_products_file_raw (
    nifi_raw_record_id uuid primary key default gen_random_uuid(),
    product_id text,
    sku text,
    product_name text,
    category text,
    supplier_id text,
    unit_cost numeric(18, 4),
    product_status text,
    ingested_by text not null default 'apache_nifi',
    ingested_at timestamptz not null default now()
);