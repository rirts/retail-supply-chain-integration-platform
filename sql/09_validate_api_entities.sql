drop function if exists monitoring.validate_api_entity_batch(uuid);

create or replace function monitoring.validate_api_entity_batch(p_batch_id uuid)
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
    v_source_system text;
    v_source_count integer;
    v_accepted_count integer;
    v_rejected_count integer;
begin
    select
        bal.entity_name,
        bal.source_system,
        bal.source_count
    into
        v_entity_name,
        v_source_system,
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
          and bal.batch_type = 'API'
          and bal.status = 'RAW_LOADED'
    ) then
        raise exception 'Batch ID % must be an API batch with RAW_LOADED status before validation', p_batch_id;
    end if;

    delete from monitoring.validation_results where validation_results.batch_id = p_batch_id;
    delete from monitoring.rejected_records where rejected_records.batch_id = p_batch_id;

    if v_entity_name = 'sales_orders' then
        delete from staging.stg_sales_orders where stg_sales_orders.batch_id = p_batch_id;
    elsif v_entity_name = 'purchase_orders' then
        delete from staging.stg_purchase_orders where stg_purchase_orders.batch_id = p_batch_id;
    elsif v_entity_name = 'shipments' then
        delete from staging.stg_shipments where stg_shipments.batch_id = p_batch_id;
    else
        raise exception 'Unsupported API entity_name: %', v_entity_name;
    end if;

    drop table if exists tmp_api_validation_records;

    create temporary table tmp_api_validation_records (
        raw_record_id uuid,
        batch_id uuid,
        source_system text,
        entity_name text,
        raw_payload jsonb,
        record_key text,
        validation_errors text[]
    ) on commit drop;

    if v_entity_name = 'sales_orders' then

        insert into tmp_api_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            record_key,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                raw_payload,
                trim(coalesce(raw_payload ->> 'sales_order_id', '')) as sales_order_id,
                trim(coalesce(raw_payload ->> 'sales_order_line_id', '')) as sales_order_line_id,
                trim(coalesce(raw_payload ->> 'product_id', '')) as product_id,
                trim(coalesce(raw_payload ->> 'location_id', '')) as location_id,
                upper(trim(coalesce(raw_payload ->> 'customer_channel', ''))) as customer_channel,
                upper(trim(coalesce(raw_payload ->> 'order_status', ''))) as order_status,
                nullif(raw_payload ->> 'order_date', '')::timestamptz as order_date,
                nullif(raw_payload ->> 'requested_ship_date', '')::timestamptz as requested_ship_date,
                case
                    when trim(coalesce(raw_payload ->> 'quantity_ordered', '')) ~ '^-?[0-9]+$'
                    then trim(coalesce(raw_payload ->> 'quantity_ordered', ''))::integer
                    else null
                end as quantity_ordered,
                case
                    when trim(coalesce(raw_payload ->> 'unit_price', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
                    then trim(coalesce(raw_payload ->> 'unit_price', ''))::numeric(18, 4)
                    else null
                end as unit_price,
                nullif(raw_payload ->> 'updated_at', '')::timestamptz as updated_at
            from raw.api_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'sales_orders'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by sales_order_line_id) as sales_order_line_id_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            sales_order_line_id as record_key,
            array_remove(array[
                case when sales_order_id = '' then 'sales_order_id is required' end,
                case when sales_order_line_id = '' then 'sales_order_line_id is required' end,
                case when sales_order_line_id <> '' and sales_order_line_id_count > 1 then 'sales_order_line_id is duplicated within batch' end,
                case when product_id = '' then 'product_id is required' end,
                case when location_id = '' then 'location_id is required' end,
                case when customer_channel not in ('ECOMMERCE', 'RETAIL_STORE', 'WHOLESALE') then 'customer_channel is invalid' end,
                case when order_status not in ('CREATED', 'CONFIRMED', 'ALLOCATED', 'SHIPPED', 'CANCELLED') then 'order_status is invalid' end,
                case when order_date is null then 'order_date is required' end,
                case when requested_ship_date is null then 'requested_ship_date is required' end,
                case when requested_ship_date is not null and order_date is not null and requested_ship_date < order_date then 'requested_ship_date cannot be before order_date' end,
                case when quantity_ordered is null then 'quantity_ordered is required or invalid' end,
                case when quantity_ordered is not null and quantity_ordered <= 0 then 'quantity_ordered must be greater than zero' end,
                case when unit_price is null then 'unit_price is required or invalid' end,
                case when unit_price is not null and unit_price <= 0 then 'unit_price must be greater than zero' end,
                case when updated_at is null then 'updated_at is required' end,
                case
                    when product_id <> ''
                     and not exists (
                        select 1
                        from target.dim_product p
                        where p.product_id = enriched.product_id
                     )
                    then 'product_id does not reference target.dim_product'
                end,
                case
                    when location_id <> ''
                     and not exists (
                        select 1
                        from target.dim_location l
                        where l.location_id = enriched.location_id
                     )
                    then 'location_id does not reference target.dim_location'
                end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_sales_orders (
            batch_id,
            sales_order_id,
            sales_order_line_id,
            product_id,
            location_id,
            customer_channel,
            order_status,
            order_date,
            requested_ship_date,
            quantity_ordered,
            unit_price,
            updated_at,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            p_batch_id,
            raw_payload ->> 'sales_order_id',
            raw_payload ->> 'sales_order_line_id',
            raw_payload ->> 'product_id',
            raw_payload ->> 'location_id',
            raw_payload ->> 'customer_channel',
            raw_payload ->> 'order_status',
            nullif(raw_payload ->> 'order_date', '')::timestamptz,
            nullif(raw_payload ->> 'requested_ship_date', '')::timestamptz,
            nullif(raw_payload ->> 'quantity_ordered', '')::integer,
            nullif(raw_payload ->> 'unit_price', '')::numeric(18, 4),
            nullif(raw_payload ->> 'updated_at', '')::timestamptz,
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_api_validation_records;

    elsif v_entity_name = 'purchase_orders' then

        insert into tmp_api_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            record_key,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                raw_payload,
                trim(coalesce(raw_payload ->> 'purchase_order_id', '')) as purchase_order_id,
                trim(coalesce(raw_payload ->> 'purchase_order_line_id', '')) as purchase_order_line_id,
                trim(coalesce(raw_payload ->> 'supplier_id', '')) as supplier_id,
                trim(coalesce(raw_payload ->> 'product_id', '')) as product_id,
                trim(coalesce(raw_payload ->> 'destination_location_id', '')) as destination_location_id,
                upper(trim(coalesce(raw_payload ->> 'purchase_order_status', ''))) as purchase_order_status,
                nullif(raw_payload ->> 'order_date', '')::timestamptz as order_date,
                nullif(raw_payload ->> 'expected_delivery_date', '')::timestamptz as expected_delivery_date,
                case
                    when trim(coalesce(raw_payload ->> 'quantity_ordered', '')) ~ '^-?[0-9]+$'
                    then trim(coalesce(raw_payload ->> 'quantity_ordered', ''))::integer
                    else null
                end as quantity_ordered,
                case
                    when trim(coalesce(raw_payload ->> 'unit_cost', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
                    then trim(coalesce(raw_payload ->> 'unit_cost', ''))::numeric(18, 4)
                    else null
                end as unit_cost,
                nullif(raw_payload ->> 'updated_at', '')::timestamptz as updated_at
            from raw.api_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'purchase_orders'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by purchase_order_line_id) as purchase_order_line_id_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            purchase_order_line_id as record_key,
            array_remove(array[
                case when purchase_order_id = '' then 'purchase_order_id is required' end,
                case when purchase_order_line_id = '' then 'purchase_order_line_id is required' end,
                case when purchase_order_line_id <> '' and purchase_order_line_id_count > 1 then 'purchase_order_line_id is duplicated within batch' end,
                case when supplier_id = '' then 'supplier_id is required' end,
                case when product_id = '' then 'product_id is required' end,
                case when destination_location_id = '' then 'destination_location_id is required' end,
                case when purchase_order_status not in ('CREATED', 'APPROVED', 'IN_TRANSIT', 'RECEIVED', 'CANCELLED') then 'purchase_order_status is invalid' end,
                case when order_date is null then 'order_date is required' end,
                case when expected_delivery_date is null then 'expected_delivery_date is required' end,
                case when expected_delivery_date is not null and order_date is not null and expected_delivery_date < order_date then 'expected_delivery_date cannot be before order_date' end,
                case when quantity_ordered is null then 'quantity_ordered is required or invalid' end,
                case when quantity_ordered is not null and quantity_ordered <= 0 then 'quantity_ordered must be greater than zero' end,
                case when unit_cost is null then 'unit_cost is required or invalid' end,
                case when unit_cost is not null and unit_cost <= 0 then 'unit_cost must be greater than zero' end,
                case when updated_at is null then 'updated_at is required' end,
                case
                    when supplier_id <> ''
                     and not exists (
                        select 1
                        from target.dim_supplier s
                        where s.supplier_id = enriched.supplier_id
                     )
                    then 'supplier_id does not reference target.dim_supplier'
                end,
                case
                    when product_id <> ''
                     and not exists (
                        select 1
                        from target.dim_product p
                        where p.product_id = enriched.product_id
                     )
                    then 'product_id does not reference target.dim_product'
                end,
                case
                    when destination_location_id <> ''
                     and not exists (
                        select 1
                        from target.dim_location l
                        where l.location_id = enriched.destination_location_id
                     )
                    then 'destination_location_id does not reference target.dim_location'
                end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_purchase_orders (
            batch_id,
            purchase_order_id,
            purchase_order_line_id,
            supplier_id,
            product_id,
            destination_location_id,
            purchase_order_status,
            order_date,
            expected_delivery_date,
            quantity_ordered,
            unit_cost,
            updated_at,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            p_batch_id,
            raw_payload ->> 'purchase_order_id',
            raw_payload ->> 'purchase_order_line_id',
            raw_payload ->> 'supplier_id',
            raw_payload ->> 'product_id',
            raw_payload ->> 'destination_location_id',
            raw_payload ->> 'purchase_order_status',
            nullif(raw_payload ->> 'order_date', '')::timestamptz,
            nullif(raw_payload ->> 'expected_delivery_date', '')::timestamptz,
            nullif(raw_payload ->> 'quantity_ordered', '')::integer,
            nullif(raw_payload ->> 'unit_cost', '')::numeric(18, 4),
            nullif(raw_payload ->> 'updated_at', '')::timestamptz,
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_api_validation_records;

    elsif v_entity_name = 'shipments' then

        insert into tmp_api_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            record_key,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                raw_payload,
                trim(coalesce(raw_payload ->> 'shipment_id', '')) as shipment_id,
                upper(trim(coalesce(raw_payload ->> 'related_order_type', ''))) as related_order_type,
                trim(coalesce(raw_payload ->> 'related_order_id', '')) as related_order_id,
                trim(coalesce(raw_payload ->> 'product_id', '')) as product_id,
                trim(coalesce(raw_payload ->> 'origin_location_id', '')) as origin_location_id,
                trim(coalesce(raw_payload ->> 'destination_location_id', '')) as destination_location_id,
                upper(trim(coalesce(raw_payload ->> 'carrier', ''))) as carrier,
                upper(trim(coalesce(raw_payload ->> 'shipment_status', ''))) as shipment_status,
                nullif(raw_payload ->> 'shipped_at', '')::timestamptz as shipped_at,
                nullif(raw_payload ->> 'delivered_at', '')::timestamptz as delivered_at,
                case
                    when trim(coalesce(raw_payload ->> 'quantity_shipped', '')) ~ '^-?[0-9]+$'
                    then trim(coalesce(raw_payload ->> 'quantity_shipped', ''))::integer
                    else null
                end as quantity_shipped,
                nullif(raw_payload ->> 'updated_at', '')::timestamptz as updated_at
            from raw.api_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'shipments'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by shipment_id) as shipment_id_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            raw_payload,
            shipment_id as record_key,
            array_remove(array[
                case when shipment_id = '' then 'shipment_id is required' end,
                case when shipment_id <> '' and shipment_id_count > 1 then 'shipment_id is duplicated within batch' end,
                case when related_order_type not in ('SALES_ORDER', 'PURCHASE_ORDER') then 'related_order_type is invalid' end,
                case when related_order_id = '' then 'related_order_id is required' end,
                case when related_order_type = 'SALES_ORDER' and related_order_id not like 'SO-%' then 'sales shipment related_order_id must start with SO-' end,
                case when related_order_type = 'PURCHASE_ORDER' and related_order_id not like 'PO-%' then 'purchase shipment related_order_id must start with PO-' end,
                case when product_id = '' then 'product_id is required' end,
                case when origin_location_id = '' then 'origin_location_id is required' end,
                case when destination_location_id = '' then 'destination_location_id is required' end,
                case when carrier not in ('DHL', 'FEDEX', 'UPS', 'ESTAFETA', 'LOCAL_CARRIER') then 'carrier is invalid' end,
                case when shipment_status not in ('CREATED', 'PICKED_UP', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED') then 'shipment_status is invalid' end,
                case when shipped_at is null then 'shipped_at is required' end,
                case when delivered_at is not null and shipped_at is not null and delivered_at < shipped_at then 'delivered_at cannot be before shipped_at' end,
                case when quantity_shipped is null then 'quantity_shipped is required or invalid' end,
                case when quantity_shipped is not null and quantity_shipped <= 0 then 'quantity_shipped must be greater than zero' end,
                case when updated_at is null then 'updated_at is required' end,
                case
                    when product_id <> ''
                     and not exists (
                        select 1
                        from target.dim_product p
                        where p.product_id = enriched.product_id
                     )
                    then 'product_id does not reference target.dim_product'
                end,
                case
                    when origin_location_id <> ''
                     and not exists (
                        select 1
                        from target.dim_location l
                        where l.location_id = enriched.origin_location_id
                     )
                    then 'origin_location_id does not reference target.dim_location'
                end,
                case
                    when destination_location_id <> ''
                     and not exists (
                        select 1
                        from target.dim_location l
                        where l.location_id = enriched.destination_location_id
                     )
                    then 'destination_location_id does not reference target.dim_location'
                end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_shipments (
            batch_id,
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
            updated_at,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            p_batch_id,
            raw_payload ->> 'shipment_id',
            raw_payload ->> 'related_order_type',
            raw_payload ->> 'related_order_id',
            raw_payload ->> 'product_id',
            raw_payload ->> 'origin_location_id',
            raw_payload ->> 'destination_location_id',
            raw_payload ->> 'carrier',
            raw_payload ->> 'shipment_status',
            nullif(raw_payload ->> 'shipped_at', '')::timestamptz,
            nullif(raw_payload ->> 'delivered_at', '')::timestamptz,
            nullif(raw_payload ->> 'quantity_shipped', '')::integer,
            nullif(raw_payload ->> 'updated_at', '')::timestamptz,
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_api_validation_records;

    end if;

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
        entity_name,
        record_key,
        raw_payload,
        'API_STAGING_VALIDATION',
        array_to_string(validation_errors, '; ')
    from tmp_api_validation_records
    where cardinality(validation_errors) > 0;

    select
        count(*) filter (where cardinality(validation_errors) = 0),
        count(*) filter (where cardinality(validation_errors) > 0)
    into
        v_accepted_count,
        v_rejected_count
    from tmp_api_validation_records;

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
        v_entity_name,
        'api_record_level_validation',
        'DATA_QUALITY',
        v_source_count,
        v_rejected_count,
        case when v_rejected_count = 0 then 'PASSED' else 'FAILED' end,
        jsonb_build_object(
            'accepted_count', v_accepted_count,
            'rejected_count', v_rejected_count,
            'rejected_by_reason',
            coalesce(
                (
                    select jsonb_object_agg(reason, failed_count)
                    from (
                        select
                            reason,
                            count(*) as failed_count
                        from tmp_api_validation_records,
                        unnest(validation_errors) as reason
                        group by reason
                        order by reason
                    ) reason_counts
                ),
                '{}'::jsonb
            )
        );

    update monitoring.batch_audit_log
    set
        accepted_count = v_accepted_count,
        rejected_count = v_rejected_count,
        status = 'VALIDATED',
        updated_at = now()
    where batch_audit_log.batch_id = p_batch_id;

    return query
    select
        p_batch_id,
        v_entity_name,
        v_source_count,
        v_accepted_count,
        v_rejected_count,
        'VALIDATED'::text;
end;
$$;