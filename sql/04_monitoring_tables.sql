create table if not exists monitoring.batch_audit_log (
    batch_id uuid primary key default gen_random_uuid(),
    pipeline_name text not null,
    source_system text not null,
    entity_name text not null,
    batch_type text not null check (
        batch_type in ('FLAT_FILE', 'API', 'EVENT_STREAM', 'MANUAL')
    ),
    source_reference text,
    source_count integer not null default 0,
    accepted_count integer not null default 0,
    rejected_count integer not null default 0,
    loaded_count integer not null default 0,
    start_time timestamptz not null default now(),
    end_time timestamptz,
    status text not null default 'STARTED' check (
        status in (
            'STARTED',
            'COMPLETED',
            'COMPLETED_WITH_REJECTIONS',
            'FAILED',
            'RECONCILIATION_FAILED'
        )
    ),
    error_message text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists monitoring.rejected_records (
    rejection_id uuid primary key default gen_random_uuid(),
    batch_id uuid references monitoring.batch_audit_log(batch_id),
    source_system text not null,
    entity_name text not null,
    record_key text,
    raw_payload jsonb not null,
    rejection_stage text not null,
    rejection_reason text not null,
    rejected_at timestamptz not null default now()
);

create index if not exists idx_rejected_records_batch_id
    on monitoring.rejected_records(batch_id);

create index if not exists idx_rejected_records_entity_name
    on monitoring.rejected_records(entity_name);

create table if not exists monitoring.validation_results (
    validation_result_id uuid primary key default gen_random_uuid(),
    batch_id uuid references monitoring.batch_audit_log(batch_id),
    entity_name text not null,
    validation_name text not null,
    validation_type text not null,
    records_checked integer not null default 0,
    records_failed integer not null default 0,
    status text not null check (status in ('PASSED', 'FAILED', 'WARNING')),
    details jsonb,
    validated_at timestamptz not null default now()
);

create table if not exists monitoring.reconciliation_results (
    reconciliation_id uuid primary key default gen_random_uuid(),
    batch_id uuid references monitoring.batch_audit_log(batch_id),
    entity_name text not null,
    source_count integer not null,
    accepted_count integer not null,
    rejected_count integer not null,
    loaded_count integer not null,
    count_difference integer not null,
    status text not null check (
        status in ('MATCHED', 'MISMATCHED', 'MATCHED_WITH_REJECTIONS')
    ),
    details jsonb,
    reconciled_at timestamptz not null default now()
);