drop function if exists target.load_validated_master_data_batch(uuid);

create or replace function target.load_validated_master_data_batch(p_batch_id uuid)
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
          and bal.status = 'VALIDATED'
    ) then
        raise exception 'Batch ID % must be VALIDATED before loading target tables', p_batch_id;
    end if;

    delete from monitoring.reconciliation_results
    where reconciliation_results.batch_id = p_batch_id;

    if v_entity_name = 'suppliers' then

        with upserted as (
            insert into target.dim_supplier (
                supplier_id,
                supplier_name,
                country_code,
                supplier_status,
                source_system,
                first_seen_at,
                last_updated_at
            )
            select
                supplier_id,
                supplier_name,
                country_code,
                supplier_status,
                source_system,
                now(),
                now()
            from staging.stg_suppliers
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (supplier_id)
            do update set
                supplier_name = excluded.supplier_name,
                country_code = excluded.country_code,
                supplier_status = excluded.supplier_status,
                source_system = excluded.source_system,
                last_updated_at = now()
            returning supplier_id
        )
        select count(*) into v_loaded_count
        from upserted;

    elsif v_entity_name = 'locations' then

        with upserted as (
            insert into target.dim_location (
                location_id,
                location_name,
                location_type,
                region,
                country_code,
                location_status,
                source_system,
                first_seen_at,
                last_updated_at
            )
            select
                location_id,
                location_name,
                location_type,
                region,
                country_code,
                location_status,
                source_system,
                now(),
                now()
            from staging.stg_locations
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (location_id)
            do update set
                location_name = excluded.location_name,
                location_type = excluded.location_type,
                region = excluded.region,
                country_code = excluded.country_code,
                location_status = excluded.location_status,
                source_system = excluded.source_system,
                last_updated_at = now()
            returning location_id
        )
        select count(*) into v_loaded_count
        from upserted;

    elsif v_entity_name = 'products' then

        with upserted as (
            insert into target.dim_product (
                product_id,
                sku,
                product_name,
                category,
                supplier_id,
                unit_cost,
                product_status,
                source_system,
                first_seen_at,
                last_updated_at
            )
            select
                product_id,
                sku,
                product_name,
                category,
                supplier_id,
                unit_cost,
                product_status,
                source_system,
                now(),
                now()
            from staging.stg_products
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (product_id)
            do update set
                sku = excluded.sku,
                product_name = excluded.product_name,
                category = excluded.category,
                supplier_id = excluded.supplier_id,
                unit_cost = excluded.unit_cost,
                product_status = excluded.product_status,
                source_system = excluded.source_system,
                last_updated_at = now()
            returning product_id
        )
        select count(*) into v_loaded_count
        from upserted;

    else
        raise exception 'Unsupported entity_name: %', v_entity_name;
    end if;

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
            'reconciliation_rule', 'accepted_count must equal loaded_count',
            'source_count_equals_accepted_plus_rejected', v_source_count = (v_accepted_count + v_rejected_count),
            'accepted_count_equals_loaded_count', v_accepted_count = v_loaded_count
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