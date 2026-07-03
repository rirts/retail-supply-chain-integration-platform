alter table monitoring.batch_audit_log
drop constraint if exists batch_audit_log_status_check;

alter table monitoring.batch_audit_log
add constraint batch_audit_log_status_check
check (
    status in (
        'STARTED',
        'RAW_LOADED',
        'VALIDATED',
        'COMPLETED',
        'COMPLETED_WITH_REJECTIONS',
        'FAILED',
        'RECONCILIATION_FAILED'
    )
);

drop function if exists monitoring.validate_flat_file_master_data_batch(uuid);

create or replace function monitoring.validate_flat_file_master_data_batch(p_batch_id uuid)
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

    delete from monitoring.validation_results where validation_results.batch_id = p_batch_id;
    delete from monitoring.rejected_records where rejected_records.batch_id = p_batch_id;

    if v_entity_name = 'suppliers' then
        delete from staging.stg_suppliers where stg_suppliers.batch_id = p_batch_id;
    elsif v_entity_name = 'products' then
        delete from staging.stg_products where stg_products.batch_id = p_batch_id;
    elsif v_entity_name = 'locations' then
        delete from staging.stg_locations where stg_locations.batch_id = p_batch_id;
    else
        raise exception 'Unsupported entity_name: %', v_entity_name;
    end if;

    drop table if exists tmp_validation_records;

    create temporary table tmp_validation_records (
        raw_record_id uuid,
        batch_id uuid,
        source_system text,
        entity_name text,
        row_number integer,
        raw_payload jsonb,
        record_key text,
        parsed_payload jsonb,
        validation_errors text[]
    ) on commit drop;

    if v_entity_name = 'suppliers' then
        insert into tmp_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            record_key,
            parsed_payload,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                row_number,
                raw_payload,
                trim(coalesce(raw_payload ->> 'supplier_id', '')) as supplier_id,
                trim(coalesce(raw_payload ->> 'supplier_name', '')) as supplier_name,
                upper(trim(coalesce(raw_payload ->> 'country_code', ''))) as country_code,
                upper(trim(coalesce(raw_payload ->> 'supplier_status', ''))) as supplier_status
            from raw.file_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'suppliers'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by supplier_id) as supplier_id_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            supplier_id as record_key,
            jsonb_build_object(
                'supplier_id', supplier_id,
                'supplier_name', supplier_name,
                'country_code', country_code,
                'supplier_status', supplier_status
            ) as parsed_payload,
            array_remove(array[
                case when supplier_id = '' then 'supplier_id is required' end,
                case when supplier_name = '' then 'supplier_name is required' end,
                case when country_code not in ('US', 'MX', 'CA', 'CN', 'VN', 'IN') then 'country_code is invalid' end,
                case when supplier_status not in ('ACTIVE', 'INACTIVE', 'ON_HOLD') then 'supplier_status is invalid' end,
                case when supplier_id <> '' and supplier_id_count > 1 then 'supplier_id is duplicated within batch' end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_suppliers (
            batch_id,
            supplier_id,
            supplier_name,
            country_code,
            supplier_status,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            batch_id,
            parsed_payload ->> 'supplier_id',
            parsed_payload ->> 'supplier_name',
            parsed_payload ->> 'country_code',
            parsed_payload ->> 'supplier_status',
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_validation_records;

    elsif v_entity_name = 'products' then
        insert into tmp_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            record_key,
            parsed_payload,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                row_number,
                raw_payload,
                trim(coalesce(raw_payload ->> 'product_id', '')) as product_id,
                upper(trim(coalesce(raw_payload ->> 'sku', ''))) as sku,
                trim(coalesce(raw_payload ->> 'product_name', '')) as product_name,
                lower(trim(coalesce(raw_payload ->> 'category', ''))) as category,
                trim(coalesce(raw_payload ->> 'supplier_id', '')) as supplier_id,
                trim(coalesce(raw_payload ->> 'unit_cost', '')) as unit_cost_text,
                case
                    when trim(coalesce(raw_payload ->> 'unit_cost', '')) ~ '^-?[0-9]+(\.[0-9]+)?$'
                    then trim(coalesce(raw_payload ->> 'unit_cost', ''))::numeric(18, 4)
                    else null
                end as unit_cost,
                upper(trim(coalesce(raw_payload ->> 'product_status', ''))) as product_status
            from raw.file_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'products'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by product_id) as product_id_count,
                count(*) over (partition by sku) as sku_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            product_id as record_key,
            jsonb_build_object(
                'product_id', product_id,
                'sku', sku,
                'product_name', product_name,
                'category', category,
                'supplier_id', supplier_id,
                'unit_cost', unit_cost,
                'product_status', product_status
            ) as parsed_payload,
            array_remove(array[
                case when product_id = '' then 'product_id is required' end,
                case when sku = '' then 'sku is required' end,
                case when product_name = '' then 'product_name is required' end,
                case when category = '' then 'category is required' end,
                case when supplier_id = '' then 'supplier_id is required' end,
                case when unit_cost_text = '' then 'unit_cost is required' end,
                case when unit_cost_text <> '' and unit_cost is null then 'unit_cost is not numeric' end,
                case when unit_cost is not null and unit_cost <= 0 then 'unit_cost must be greater than zero' end,
                case when product_status not in ('ACTIVE', 'DISCONTINUED', 'SEASONAL') then 'product_status is invalid' end,
                case when product_id <> '' and product_id_count > 1 then 'product_id is duplicated within batch' end,
                case when sku <> '' and sku_count > 1 then 'sku is duplicated within batch' end,
                case
                    when supplier_id <> ''
                     and not exists (
                        select 1
                        from staging.stg_suppliers s
                        where s.supplier_id = enriched.supplier_id
                          and s.record_status = 'ACCEPTED'
                     )
                    then 'supplier_id does not reference an accepted supplier'
                end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_products (
            batch_id,
            product_id,
            sku,
            product_name,
            category,
            supplier_id,
            unit_cost,
            product_status,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            batch_id,
            parsed_payload ->> 'product_id',
            parsed_payload ->> 'sku',
            parsed_payload ->> 'product_name',
            parsed_payload ->> 'category',
            parsed_payload ->> 'supplier_id',
            nullif(parsed_payload ->> 'unit_cost', '')::numeric(18, 4),
            parsed_payload ->> 'product_status',
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_validation_records;

    elsif v_entity_name = 'locations' then
        insert into tmp_validation_records (
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            record_key,
            parsed_payload,
            validation_errors
        )
        with parsed as (
            select
                raw_record_id,
                batch_id,
                source_system,
                entity_name,
                row_number,
                raw_payload,
                trim(coalesce(raw_payload ->> 'location_id', '')) as location_id,
                trim(coalesce(raw_payload ->> 'location_name', '')) as location_name,
                upper(trim(coalesce(raw_payload ->> 'location_type', ''))) as location_type,
                lower(trim(coalesce(raw_payload ->> 'region', ''))) as region,
                upper(trim(coalesce(raw_payload ->> 'country_code', ''))) as country_code,
                upper(trim(coalesce(raw_payload ->> 'location_status', ''))) as location_status
            from raw.file_ingestion_raw
            where batch_id = p_batch_id
              and entity_name = 'locations'
        ),
        enriched as (
            select
                *,
                count(*) over (partition by location_id) as location_id_count
            from parsed
        )
        select
            raw_record_id,
            batch_id,
            source_system,
            entity_name,
            row_number,
            raw_payload,
            location_id as record_key,
            jsonb_build_object(
                'location_id', location_id,
                'location_name', location_name,
                'location_type', location_type,
                'region', region,
                'country_code', country_code,
                'location_status', location_status
            ) as parsed_payload,
            array_remove(array[
                case when location_id = '' then 'location_id is required' end,
                case when location_name = '' then 'location_name is required' end,
                case when location_type not in ('STORE', 'DC', 'WAREHOUSE') then 'location_type is invalid' end,
                case when region = '' then 'region is required' end,
                case when country_code not in ('US', 'MX', 'CA', 'CN', 'VN', 'IN') then 'country_code is invalid' end,
                case when location_status not in ('ACTIVE', 'INACTIVE') then 'location_status is invalid' end,
                case when location_id <> '' and location_id_count > 1 then 'location_id is duplicated within batch' end
            ], null) as validation_errors
        from enriched;

        insert into staging.stg_locations (
            batch_id,
            location_id,
            location_name,
            location_type,
            region,
            country_code,
            location_status,
            source_system,
            validated_at,
            record_status,
            validation_errors
        )
        select
            batch_id,
            parsed_payload ->> 'location_id',
            parsed_payload ->> 'location_name',
            parsed_payload ->> 'location_type',
            parsed_payload ->> 'region',
            parsed_payload ->> 'country_code',
            parsed_payload ->> 'location_status',
            source_system,
            now(),
            case when cardinality(validation_errors) = 0 then 'ACCEPTED' else 'REJECTED' end,
            validation_errors
        from tmp_validation_records;
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
        'STAGING_VALIDATION',
        array_to_string(validation_errors, '; ')
    from tmp_validation_records
    where cardinality(validation_errors) > 0;

    select
        count(*) filter (where cardinality(validation_errors) = 0),
        count(*) filter (where cardinality(validation_errors) > 0)
    into
        v_accepted_count,
        v_rejected_count
    from tmp_validation_records;

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
        'flat_file_record_level_validation',
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
                        from tmp_validation_records,
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