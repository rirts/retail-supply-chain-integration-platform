drop function if exists target.load_validated_inventory_event_batch(uuid);

create or replace function target.load_validated_inventory_event_batch(p_batch_id uuid)
returns table (
    result_batch_id uuid,
    result_entity_name text,
    result_source_count integer,
    result_accepted_count integer,
    result_rejected_count integer,
    result_loaded_count integer,
    result_reconciliation_status text,
    result_batch_status text
)
language plpgsql
as $$
declare
    v_entity_name text;
    v_source_count integer;
    v_accepted_count integer;
    v_rejected_count integer;
    v_loaded_count integer := 0;
    v_reconciliation_status text;
    v_batch_status text;
begin
    select
        bal.entity_name,
        bal.source_count,
        bal.accepted_count,
        bal.rejected_count
    into
        v_entity_name,
        v_source_count,
        v_accepted_count,
        v_rejected_count
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
          and bal.status = 'VALIDATED'
    ) then
        raise exception 'Batch ID % must be a VALIDATED EVENT_STREAM batch before loading targets', p_batch_id;
    end if;

    delete from monitoring.reconciliation_results
    where reconciliation_results.batch_id = p_batch_id;

    drop table if exists tmp_loaded_inventory_events;

    create temporary table tmp_loaded_inventory_events (
        event_id text,
        product_id text,
        location_id text,
        quantity_change integer,
        event_timestamp timestamptz
    ) on commit drop;

    with inserted as (
        insert into target.fact_inventory_movement (
            event_id,
            event_type,
            product_id,
            location_id,
            quantity_change,
            reason_code,
            event_timestamp,
            published_at,
            source_system,
            first_seen_at,
            last_updated_at
        )
        select
            event_id,
            event_type,
            product_id,
            location_id,
            quantity_change,
            reason_code,
            event_timestamp,
            published_at,
            source_system,
            now(),
            now()
        from staging.stg_inventory_events
        where batch_id = p_batch_id
          and record_status = 'ACCEPTED'
        on conflict (event_id)
        do nothing
        returning
            event_id,
            product_id,
            location_id,
            quantity_change,
            event_timestamp
    )
    insert into tmp_loaded_inventory_events (
        event_id,
        product_id,
        location_id,
        quantity_change,
        event_timestamp
    )
    select
        event_id,
        product_id,
        location_id,
        quantity_change,
        event_timestamp
    from inserted;

    select count(*)
    into v_loaded_count
    from tmp_loaded_inventory_events;

    insert into target.fact_inventory_snapshot (
        product_id,
        location_id,
        on_hand_quantity,
        last_event_timestamp,
        last_updated_at
    )
    select
        product_id,
        location_id,
        sum(quantity_change)::integer as on_hand_quantity,
        max(event_timestamp) as last_event_timestamp,
        now()
    from tmp_loaded_inventory_events
    group by
        product_id,
        location_id
    on conflict (product_id, location_id)
    do update set
        on_hand_quantity = target.fact_inventory_snapshot.on_hand_quantity + excluded.on_hand_quantity,
        last_event_timestamp = greatest(
            target.fact_inventory_snapshot.last_event_timestamp,
            excluded.last_event_timestamp
        ),
        last_updated_at = now();

    v_reconciliation_status :=
        case
            when v_loaded_count = v_accepted_count and v_rejected_count = 0
                then 'MATCHED'
            when v_loaded_count = v_accepted_count and v_rejected_count > 0
                then 'MATCHED_WITH_REJECTIONS'
            else 'MISMATCHED'
        end;

    v_batch_status :=
        case
            when v_reconciliation_status = 'MISMATCHED'
                then 'RECONCILIATION_FAILED'
            when v_rejected_count > 0
                then 'COMPLETED_WITH_REJECTIONS'
            else 'COMPLETED'
        end;

    insert into monitoring.reconciliation_results (
        batch_id,
        entity_name,
        source_count,
        accepted_count,
        rejected_count,
        loaded_count,
        count_difference,
        status,
        details
    )
    values (
        p_batch_id,
        v_entity_name,
        v_source_count,
        v_accepted_count,
        v_rejected_count,
        v_loaded_count,
        v_accepted_count - v_loaded_count,
        v_reconciliation_status,
        jsonb_build_object(
            'integration_type', 'EVENT_STREAM',
            'reconciliation_rule', 'accepted_count must equal loaded_count',
            'source_count_equals_accepted_plus_rejected', v_source_count = (v_accepted_count + v_rejected_count),
            'accepted_count_equals_loaded_count', v_accepted_count = v_loaded_count,
            'snapshot_rows_affected',
            (
                select count(*)
                from (
                    select product_id, location_id
                    from tmp_loaded_inventory_events
                    group by product_id, location_id
                ) snapshot_keys
            )
        )
    );

    update monitoring.batch_audit_log
    set
        loaded_count = v_loaded_count,
        status = v_batch_status,
        end_time = now(),
        updated_at = now()
    where batch_audit_log.batch_id = p_batch_id;

    return query
    select
        p_batch_id,
        v_entity_name,
        v_source_count,
        v_accepted_count,
        v_rejected_count,
        v_loaded_count,
        v_reconciliation_status,
        v_batch_status;
end;
$$;