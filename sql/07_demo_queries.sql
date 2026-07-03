-- ============================================================
-- Demo Queries: Flat File Master Data Integration
-- ============================================================

-- 1. Batch audit summary
select
    entity_name,
    batch_type,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    status,
    start_time,
    end_time
from monitoring.batch_audit_log
order by created_at;


-- 2. Source-to-target reconciliation
select
    entity_name,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status,
    details
from monitoring.reconciliation_results
order by reconciled_at;


-- 3. Rejected records by reason
select
    entity_name,
    rejection_reason,
    count(*) as rejected_count
from monitoring.rejected_records
group by 1, 2
order by entity_name, rejected_count desc;


-- 4. Target table counts
select 'target.dim_supplier' as table_name, count(*) as record_count
from target.dim_supplier

union all

select 'target.dim_product' as table_name, count(*) as record_count
from target.dim_product

union all

select 'target.dim_location' as table_name, count(*) as record_count
from target.dim_location
order by table_name;


-- 5. Accepted vs rejected staging records
select
    'suppliers' as entity_name,
    record_status,
    count(*) as record_count
from staging.stg_suppliers
group by record_status

union all

select
    'products' as entity_name,
    record_status,
    count(*) as record_count
from staging.stg_products
group by record_status

union all

select
    'locations' as entity_name,
    record_status,
    count(*) as record_count
from staging.stg_locations
group by record_status
order by entity_name, record_status;


-- 6. Sample rejected records
select
    entity_name,
    record_key,
    rejection_stage,
    rejection_reason,
    raw_payload,
    rejected_at
from monitoring.rejected_records
order by rejected_at
limit 20;


-- 7. Product records rejected because of referential integrity
select
    record_key as product_id,
    rejection_reason,
    raw_payload ->> 'supplier_id' as rejected_supplier_id,
    raw_payload
from monitoring.rejected_records
where entity_name = 'products'
  and rejection_reason ilike '%supplier_id%'
order by rejected_at;


-- 8. Final integrated product dimension sample
select
    p.product_id,
    p.sku,
    p.product_name,
    p.category,
    p.supplier_id,
    s.supplier_name,
    p.unit_cost,
    p.product_status,
    p.last_updated_at
from target.dim_product p
join target.dim_supplier s
    on p.supplier_id = s.supplier_id
order by p.product_id
limit 25;