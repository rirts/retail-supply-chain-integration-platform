drop function if exists target.load_validated_api_entity_batch(uuid);

create or replace function target.load_validated_api_entity_batch(p_batch_id uuid)
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
          and bal.batch_type = 'API'
          and bal.status = 'VALIDATED'
    ) then
        raise exception 'Batch ID % must be a VALIDATED API batch before loading target tables', p_batch_id;
    end if;

    delete from monitoring.reconciliation_results
    where reconciliation_results.batch_id = p_batch_id;

    if v_entity_name = 'sales_orders' then

        with upserted as (
            insert into target.fact_sales_order (
                sales_order_line_id,
                sales_order_id,
                product_id,
                location_id,
                customer_channel,
                order_status,
                order_date,
                requested_ship_date,
                quantity_ordered,
                unit_price,
                source_system,
                source_updated_at,
                first_seen_at,
                last_updated_at
            )
            select
                sales_order_line_id,
                sales_order_id,
                product_id,
                location_id,
                customer_channel,
                order_status,
                order_date,
                requested_ship_date,
                quantity_ordered,
                unit_price,
                source_system,
                updated_at,
                now(),
                now()
            from staging.stg_sales_orders
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (sales_order_line_id)
            do update set
                sales_order_id = excluded.sales_order_id,
                product_id = excluded.product_id,
                location_id = excluded.location_id,
                customer_channel = excluded.customer_channel,
                order_status = excluded.order_status,
                order_date = excluded.order_date,
                requested_ship_date = excluded.requested_ship_date,
                quantity_ordered = excluded.quantity_ordered,
                unit_price = excluded.unit_price,
                source_system = excluded.source_system,
                source_updated_at = excluded.source_updated_at,
                last_updated_at = now()
            returning sales_order_line_id
        )
        select count(*) into v_loaded_count
        from upserted;

    elsif v_entity_name = 'purchase_orders' then

        with upserted as (
            insert into target.fact_purchase_order (
                purchase_order_line_id,
                purchase_order_id,
                supplier_id,
                product_id,
                destination_location_id,
                purchase_order_status,
                order_date,
                expected_delivery_date,
                quantity_ordered,
                unit_cost,
                source_system,
                source_updated_at,
                first_seen_at,
                last_updated_at
            )
            select
                purchase_order_line_id,
                purchase_order_id,
                supplier_id,
                product_id,
                destination_location_id,
                purchase_order_status,
                order_date,
                expected_delivery_date,
                quantity_ordered,
                unit_cost,
                source_system,
                updated_at,
                now(),
                now()
            from staging.stg_purchase_orders
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (purchase_order_line_id)
            do update set
                purchase_order_id = excluded.purchase_order_id,
                supplier_id = excluded.supplier_id,
                product_id = excluded.product_id,
                destination_location_id = excluded.destination_location_id,
                purchase_order_status = excluded.purchase_order_status,
                order_date = excluded.order_date,
                expected_delivery_date = excluded.expected_delivery_date,
                quantity_ordered = excluded.quantity_ordered,
                unit_cost = excluded.unit_cost,
                source_system = excluded.source_system,
                source_updated_at = excluded.source_updated_at,
                last_updated_at = now()
            returning purchase_order_line_id
        )
        select count(*) into v_loaded_count
        from upserted;

    elsif v_entity_name = 'shipments' then

        with upserted as (
            insert into target.fact_shipment (
                shipment_id,
                related_order_type,
                related_order_id,
                product_id,
                origin_location_id,
                destination_location_id,
                carrier,
                shipment_status,
                shipped_at,
                delivered_at,
                quantity_shipped,
                source_system,
                source_updated_at,
                first_seen_at,
                last_updated_at
            )
            select
                shipment_id,
                related_order_type,
                related_order_id,
                product_id,
                origin_location_id,
                destination_location_id,
                carrier,
                shipment_status,
                shipped_at,
                delivered_at,
                quantity_shipped,
                source_system,
                updated_at,
                now(),
                now()
            from staging.stg_shipments
            where batch_id = p_batch_id
              and record_status = 'ACCEPTED'
            on conflict (shipment_id)
            do update set
                related_order_type = excluded.related_order_type,
                related_order_id = excluded.related_order_id,
                product_id = excluded.product_id,
                origin_location_id = excluded.origin_location_id,
                destination_location_id = excluded.destination_location_id,
                carrier = excluded.carrier,
                shipment_status = excluded.shipment_status,
                shipped_at = excluded.shipped_at,
                delivered_at = excluded.delivered_at,
                quantity_shipped = excluded.quantity_shipped,
                source_system = excluded.source_system,
                source_updated_at = excluded.source_updated_at,
                last_updated_at = now()
            returning shipment_id
        )
        select count(*) into v_loaded_count
        from upserted;

    else
        raise exception 'Unsupported API entity_name: %', v_entity_name;
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
            'integration_type', 'API',
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