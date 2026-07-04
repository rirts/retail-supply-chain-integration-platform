create table if not exists raw.nifi_sales_orders_api_raw (
    nifi_raw_record_id uuid primary key default gen_random_uuid(),
    sales_order_id text,
    sales_order_line_id text,
    product_id text,
    location_id text,
    customer_channel text,
    order_status text,
    order_date text,
    requested_ship_date text,
    quantity_ordered integer,
    unit_price numeric(18, 4),
    updated_at text,
    ingested_by text not null default 'apache_nifi',
    ingested_at timestamptz not null default now()
);