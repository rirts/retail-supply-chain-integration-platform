create table if not exists staging.stg_sales_orders (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    sales_order_id text not null,
    sales_order_line_id text not null,
    product_id text,
    location_id text,
    customer_channel text,
    order_status text,
    order_date timestamptz,
    requested_ship_date timestamptz,
    quantity_ordered integer,
    unit_price numeric(18, 4),
    updated_at timestamptz,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists staging.stg_purchase_orders (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    purchase_order_id text not null,
    purchase_order_line_id text not null,
    supplier_id text,
    product_id text,
    destination_location_id text,
    purchase_order_status text,
    order_date timestamptz,
    expected_delivery_date timestamptz,
    quantity_ordered integer,
    unit_cost numeric(18, 4),
    updated_at timestamptz,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists staging.stg_shipments (
    staging_record_id uuid primary key default gen_random_uuid(),
    batch_id uuid not null,
    shipment_id text not null,
    related_order_type text,
    related_order_id text,
    product_id text,
    origin_location_id text,
    destination_location_id text,
    carrier text,
    shipment_status text,
    shipped_at timestamptz,
    delivered_at timestamptz,
    quantity_shipped integer,
    updated_at timestamptz,
    source_system text not null,
    validated_at timestamptz,
    record_status text not null default 'PENDING_VALIDATION',
    validation_errors text[],
    created_at timestamptz not null default now()
);

create table if not exists target.fact_sales_order (
    sales_order_line_id text primary key,
    sales_order_id text not null,
    product_id text not null references target.dim_product(product_id),
    location_id text not null references target.dim_location(location_id),
    customer_channel text not null,
    order_status text not null,
    order_date timestamptz not null,
    requested_ship_date timestamptz not null,
    quantity_ordered integer not null,
    unit_price numeric(18, 4) not null,
    source_system text not null,
    source_updated_at timestamptz not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);

create table if not exists target.fact_purchase_order (
    purchase_order_line_id text primary key,
    purchase_order_id text not null,
    supplier_id text not null references target.dim_supplier(supplier_id),
    product_id text not null references target.dim_product(product_id),
    destination_location_id text not null references target.dim_location(location_id),
    purchase_order_status text not null,
    order_date timestamptz not null,
    expected_delivery_date timestamptz not null,
    quantity_ordered integer not null,
    unit_cost numeric(18, 4) not null,
    source_system text not null,
    source_updated_at timestamptz not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);

create table if not exists target.fact_shipment (
    shipment_id text primary key,
    related_order_type text not null,
    related_order_id text not null,
    product_id text not null references target.dim_product(product_id),
    origin_location_id text not null references target.dim_location(location_id),
    destination_location_id text not null references target.dim_location(location_id),
    carrier text not null,
    shipment_status text not null,
    shipped_at timestamptz not null,
    delivered_at timestamptz,
    quantity_shipped integer not null,
    source_system text not null,
    source_updated_at timestamptz not null,
    first_seen_at timestamptz not null default now(),
    last_updated_at timestamptz not null default now()
);