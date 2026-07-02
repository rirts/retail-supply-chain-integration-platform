create table if not exists target.dim_supplier (
    supplier_id text primary key,
    supplier_name text not null,
    country_code text not null,
    supplier_status text not null,
    source_system text not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);

create table if not exists target.dim_product (
    product_id text primary key,
    sku text not null unique,
    product_name text not null,
    category text not null,
    supplier_id text not null references target.dim_supplier(supplier_id),
    unit_cost numeric(18, 4) not null,
    product_status text not null,
    source_system text not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);

create table if not exists target.dim_location (
    location_id text primary key,
    location_name text not null,
    location_type text not null,
    region text not null,
    country_code text not null,
    location_status text not null,
    source_system text not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);