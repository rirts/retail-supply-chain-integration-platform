drop function if exists monitoring.validate_inventory_event_batch(uuid);

create or replace function monitoring.validate_inventory_event_batch(p_batch_id uuid)
returns table (
    result_batch_id uuid,
    result_entity_name text,
    result_source_count integer,
    result_accepted_count integer,
    result_rejected_count integer,
    result_status text
)
language plpgsql
as $$
declare
    v_entity_name text;
    v_source_count integer;
    v_duplicate_rejected_count integer := 0;
    v_validation_rejected_count integer := 0;
    v_accepted_count integer := 0;
    v_total_rejected_count integer := 0;
begin
    select
        bal.entity_name,
        bal.source_count
    into
        v_entity_name,
        v_source_count
    from monitoring.batch_audit_log bal
    where bal.batch_id = p_batch_id;

    if v_entity_name is null then
        raise exception 'Batch ID % not found in monitoring.batch_audit_log', p_batch_id;
    end if;

    if not exists (
        select 1
        from monitoring.batch_audit_log bal
        where bal.batch_id = p_batch_id
          and bal.batch_type = 'EVENT_STREAM'
          and bal.status = 'RAW_LOADED'
    ) then
        raise exception 'Batch ID % must be an EVENT_STREAM batch with RAW_LOADED status before validation', p_batch_id;
    end if;

    delete from monitoring.validation_results where validation_results.batch_id = p_batch_id;
    delete from monitoring.rejected_records
    where rejected_records.batch_id = p_batch_id
      and rejected_records.rejection_stage = 'EVENT_STAGING_VALIDATION';

    delete from staging.stg_inventory_events
    where stg_inventory_events.batch_id = p_batch_id;

    select count(*)
    into v_duplicate_rejected_count
    from monitoring.rejected_records
    where batch_id = p_batch_id
      and rejection_stage = 'EVENT_DEDUPLICATION';

    drop table if exists tmp_inventory_event_validation;

    create temporary table tmp_inventory_event_validation (
        raw_event_id uuid,
        batch_id uuid,
        source_system text,
        raw_payload jsonb,
        record_key text,
        validation_errors text[]
    ) on commit drop;

    insert into tmp_inventory_event_validation (
        raw_event_id,
        batch_id,
        source_system,
        raw_payload,
        record_key,
        validation_errors
    )
    with parsed as (
        select
            raw_event_id,
            batch_id,
            source_system,
            raw_payload,
            trim(coalesce(raw_payload ->> 'event_id', '')) as event_id,
            upper(trim(coalesce(raw_payload ->> 'event_type', ''))) as event_type,
            trim(coalesce(raw_payload ->> 'product_id', '')) as product_id,
            trim(coalesce(raw_payload ->> 'location_id', '')) as location_id,
            case
                when trim(coalesce(raw_payload ->> 'quantity_change', '')) ~ '^-?[0-9]+$'
                then monitoring.try_integer(raw_payload ->> 'quantity_change')
                else null
            end as quantity_change,
            upper(trim(coalesce(raw_payload ->> 'reason_code', ''))) as reason_code,
            monitoring.try_timestamptz(raw_payload ->> 'event_timestamp') as event_timestamp,
            monitoring.try_timestamptz(raw_payload ->> 'published_at') as published_at
        from raw.inventory_events_raw
        where batch_id = p_batch_id
    )
    select
        raw_event_id,
        batch_id,
        source_system,
        raw_payload,
        event_id as record_key,
        array_remove(array[
            case when event_id = '' then 'event_id is required' end,
            case when event_type not in (
                'INVENTORY_RECEIVED',
                'INVENTORY_ADJUSTED',
                'INVENTORY_TRANSFERRED',
                'INVENTORY_RESERVED',
                'INVENTORY_RELEASED'
            ) then 'event_type is invalid' end,
            case when product_id = '' then 'product_id is required' end,
            case when location_id = '' then 'location_id is required' end,
            case when quantity_change is null then 'quantity_change is required or invalid' end,
            case when quantity_change = 0 then 'quantity_change cannot be zero' end,
            case when reason_code not in (
                'PURCHASE_ORDER_RECEIPT',
                'SALES_ORDER_RESERVATION',
                'CYCLE_COUNT_ADJUSTMENT',
                'TRANSFER_OUT',
                'TRANSFER_IN',
                'DAMAGED_GOODS'
            ) then 'reason_code is invalid' end,
            case when event_timestamp is null then 'event_timestamp is required' end,
            case when published_at is null then 'published_at is required' end,
            case when event_timestamp is not null and published_at is not null and published_at < event_timestamp then 'published_at cannot be before event_timestamp' end,
            case
                when product_id <> ''
                 and not exists (
                    select 1
                    from target.dim_product p
                    where p.product_id = parsed.product_id
                 )
                then 'product_id does not reference target.dim_product'
            end,
            case
                when location_id <> ''
                 and not exists (
                    select 1
                    from target.dim_location l
                    where l.location_id = parsed.location_id
                 )
                then 'location_id does not reference target.dim_location'
            end
        ], null) as validation_errors
    from parsed;

    insert into staging.stg_inventory_events (
        batch_id,
        event_id,
        event_type,
        product_id,
        location_id,
        quantity_change,
        reason_code,
        event_timestamp,
        published_at,
        source_system,
        validated_at,
        record_status,
        validation_errors
    )
    select
        p_batch_id,
        coalesce(raw_payload ->> 'event_id', ''),
        raw_payload ->> 'event_type',
        raw_payload ->> 'product_id',
        raw_payload ->> 'location_id',
        monitoring.try_integer(raw_payload ->> 'quantity_change'),
        raw_payload ->> 'reason_code',
        monitoring.try_timestamptz(raw_payload ->> 'event_timestamp'),
        monitoring.try_timestamptz(raw_payload ->> 'published_at'),
        source_system,
        now(),
        case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
        validation_errors
    from tmp_inventory_event_validation;

    insert into monitoring.rejected_records (
        batch_id,
        source_system,
        entity_name,
        record_key,
        raw_payload,
        rejection_stage,
        rejection_reason
    )
    select
        batch_id,
        source_system,
        'inventory_events',
        record_key,
        raw_payload,
        'EVENT_STAGING_VALIDATION',
        array_to_string(validation_errors, '; ')
    from tmp_inventory_event_validation
    where cardinality(validation_errors) > 0;

    select
        count(*) filter (where cardinality(validation_errors) = 0),
        count(*) filter (where cardinality(validation_errors) > 0)
    into
        v_accepted_count,
        v_validation_rejected_count
    from tmp_inventory_event_validation;

    v_total_rejected_count := v_validation_rejected_count + v_duplicate_rejected_count;

    insert into monitoring.validation_results (
        batch_id,
        entity_name,
        validation_name,
        validation_type,
        records_checked,
        records_failed,
        status,
        details
    )
    select
        p_batch_id,
        'inventory_events',
        'inventory_event_stream_validation',
        'EVENT_STREAM_DATA_QUALITY',
        v_source_count,
        v_total_rejected_count,
        case when v_total_rejected_count = 0 then 'PASSED' else 'FAILED' end,
        jsonb_build_object(
            'accepted_count', v_accepted_count,
            'validation_rejected_count', v_validation_rejected_count,
            'duplicate_rejected_count', v_duplicate_rejected_count,
            'total_rejected_count', v_total_rejected_count
        );

    update monitoring.batch_audit_log
    set
        accepted_count = v_accepted_count,
        rejected_count = v_total_rejected_count,
        status = 'VALIDATED',
        updated_at = now()
    where batch_audit_log.batch_id = p_batch_id;

    return query
    select
        p_batch_id,
        'inventory_events'::text,
        v_source_count,
        v_accepted_count,
        v_total_rejected_count,
        'VALIDATED'::text;
end;
$$;