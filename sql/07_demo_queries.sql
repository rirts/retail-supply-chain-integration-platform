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

-- ============================================================
-- Demo Queries: API-Based Integration
-- ============================================================

-- 9. API batch audit summary
select
    entity_name,
    batch_type,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    status,
    source_reference,
    start_time,
    end_time
from monitoring.batch_audit_log
where batch_type = 'API'
order by created_at;


-- 10. API source-to-target reconciliation
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
where entity_name in ('sales_orders', 'purchase_orders', 'shipments')
order by reconciled_at;


-- 11. API rejected records by reason
select
    entity_name,
    rejection_reason,
    count(*) as rejected_count
from monitoring.rejected_records
where rejection_stage = 'API_STAGING_VALIDATION'
group by 1, 2
order by entity_name, rejected_count desc;


-- 12. API target fact counts
select 'target.fact_sales_order' as table_name, count(*) as record_count
from target.fact_sales_order

union all

select 'target.fact_purchase_order' as table_name, count(*) as record_count
from target.fact_purchase_order

union all

select 'target.fact_shipment' as table_name, count(*) as record_count
from target.fact_shipment
order by table_name;


-- 13. Integrated sales order sample
select
    so.sales_order_line_id,
    so.sales_order_id,
    so.product_id,
    p.sku,
    p.product_name,
    so.location_id,
    l.location_name,
    so.customer_channel,
    so.order_status,
    so.quantity_ordered,
    so.unit_price,
    so.source_updated_at
from target.fact_sales_order so
join target.dim_product p
    on so.product_id = p.product_id
join target.dim_location l
    on so.location_id = l.location_id
order by so.sales_order_line_id
limit 25;


-- 14. Integrated purchase order sample
select
    po.purchase_order_line_id,
    po.purchase_order_id,
    po.supplier_id,
    s.supplier_name,
    po.product_id,
    p.sku,
    po.destination_location_id,
    l.location_name,
    po.purchase_order_status,
    po.quantity_ordered,
    po.unit_cost,
    po.source_updated_at
from target.fact_purchase_order po
join target.dim_supplier s
    on po.supplier_id = s.supplier_id
join target.dim_product p
    on po.product_id = p.product_id
join target.dim_location l
    on po.destination_location_id = l.location_id
order by po.purchase_order_line_id
limit 25;


-- 15. Integrated shipment sample
select
    sh.shipment_id,
    sh.related_order_type,
    sh.related_order_id,
    sh.product_id,
    p.sku,
    sh.origin_location_id,
    origin_l.location_name as origin_location_name,
    sh.destination_location_id,
    dest_l.location_name as destination_location_name,
    sh.carrier,
    sh.shipment_status,
    sh.quantity_shipped,
    sh.source_updated_at
from target.fact_shipment sh
join target.dim_product p
    on sh.product_id = p.product_id
join target.dim_location origin_l
    on sh.origin_location_id = origin_l.location_id
join target.dim_location dest_l
    on sh.destination_location_id = dest_l.location_id
order by sh.shipment_id
limit 25;

-- ============================================================
-- Demo Queries: Event-Based Inventory Integration
-- ============================================================

-- 16. Event stream batch audit summary
select
    entity_name,
    batch_type,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    status,
    error_message,
    start_time,
    end_time
from monitoring.batch_audit_log
where batch_type = 'EVENT_STREAM'
order by created_at;


-- 17. Event stream reconciliation
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
where entity_name = 'inventory_events'
order by reconciled_at;


-- 18. Inventory event rejected records by reason
select
    rejection_stage,
    rejection_reason,
    count(*) as rejected_count
from monitoring.rejected_records
where entity_name = 'inventory_events'
group by 1, 2
order by rejection_stage, rejected_count desc;


-- 19. Inventory target counts
select 'target.fact_inventory_movement' as table_name, count(*) as record_count
from target.fact_inventory_movement

union all

select 'target.fact_inventory_snapshot' as table_name, count(*) as record_count
from target.fact_inventory_snapshot
order by table_name;


-- 20. Integrated inventory movement sample
select
    im.event_id,
    im.event_type,
    im.product_id,
    p.sku,
    p.product_name,
    im.location_id,
    l.location_name,
    im.quantity_change,
    im.reason_code,
    im.event_timestamp,
    im.published_at
from target.fact_inventory_movement im
join target.dim_product p
    on im.product_id = p.product_id
join target.dim_location l
    on im.location_id = l.location_id
order by im.event_timestamp
limit 25;


-- 21. Inventory snapshot sample
select
    s.product_id,
    p.sku,
    p.product_name,
    s.location_id,
    l.location_name,
    s.on_hand_quantity,
    s.last_event_timestamp,
    s.last_updated_at
from target.fact_inventory_snapshot s
join target.dim_product p
    on s.product_id = p.product_id
join target.dim_location l
    on s.location_id = l.location_id
order by abs(s.on_hand_quantity) desc
limit 25;