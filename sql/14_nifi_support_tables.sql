create table if not exists monitoring.nifi_connectivity_test (
    test_id uuid primary key default gen_random_uuid(),
    test_name text not null,
    test_status text not null,
    details text,
    created_at timestamptz not null default now()
);