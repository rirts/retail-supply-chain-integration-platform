\pset pager off

\echo ''
\echo '============================================================'
\echo 'RETAIL SUPPLY CHAIN INTEGRATION PLATFORM - DEMO QUERIES'
\echo '============================================================'
\echo ''

\echo ''
\echo '1. Target table counts'
\echo '------------------------------------------------------------'

select 'target.dim_supplier' as table_name, count(*) as row_count from target.dim_supplier
union all
select 'target.dim_product', count(*) from target.dim_product
union all
select 'target.dim_location', count(*) from target.dim_location
union all
select 'target.fact_sales_order', count(*) from target.fact_sales_order
union all
select 'target.fact_purchase_order', count(*) from target.fact_purchase_order
union all
select 'target.fact_shipment', count(*) from target.fact_shipment
union all
select 'target.fact_inventory_movement', count(*) from target.fact_inventory_movement
union all
select 'target.fact_inventory_snapshot', count(*) from target.fact_inventory_snapshot
order by table_name;

\echo ''
\echo '2. Latest batch audit log'
\echo '------------------------------------------------------------'

select
    entity_name,
    batch_type,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    status,
    created_at,
    updated_at
from monitoring.batch_audit_log
order by created_at desc
limit 20;

\echo ''
\echo '3. Rejected records by entity, stage, and reason'
\echo '------------------------------------------------------------'

select
    entity_name,
    rejection_stage,
    rejection_reason,
    count(*) as rejected_count
from monitoring.rejected_records
group by
    entity_name,
    rejection_stage,
    rejection_reason
order by
    entity_name,
    rejected_count desc,
    rejection_reason;

\echo ''
\echo '4. Source-to-target reconciliation results'
\echo '------------------------------------------------------------'

select
    entity_name,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status,
    reconciled_at
from monitoring.reconciliation_results
order by reconciled_at desc
limit 20;

\echo ''
\echo '5. Reconciliation health check'
\echo '------------------------------------------------------------'

select
    entity_name,
    case
        when source_count = accepted_count + rejected_count
         and accepted_count = loaded_count
         and count_difference = 0
        then 'PASS'
        else 'FAIL'
    end as reconciliation_check,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status
from monitoring.reconciliation_results
order by reconciled_at desc
limit 20;

\echo ''
\echo '6. Flat-file master data summary'
\echo '------------------------------------------------------------'

select
    'suppliers' as entity_name,
    count(*) as target_count
from target.dim_supplier
union all
select
    'products',
    count(*)
from target.dim_product
union all
select
    'locations',
    count(*)
from target.dim_location
order by entity_name;

\echo ''
\echo '7. API fact table summary'
\echo '------------------------------------------------------------'

select
    'sales_orders' as entity_name,
    count(*) as target_count
from target.fact_sales_order
union all
select
    'purchase_orders',
    count(*)
from target.fact_purchase_order
union all
select
    'shipments',
    count(*)
from target.fact_shipment
order by entity_name;

\echo ''
\echo '8. Sales orders by status'
\echo '------------------------------------------------------------'

select
    order_status,
    count(*) as order_count,
    sum(quantity_ordered) as total_quantity,
    round(sum(quantity_ordered * unit_price), 2) as gross_order_value
from target.fact_sales_order
group by order_status
order by order_count desc;

\echo ''
\echo '9. Purchase orders by status'
\echo '------------------------------------------------------------'

select
    order_status,
    count(*) as purchase_order_count,
    sum(quantity_ordered) as total_quantity,
    round(sum(quantity_ordered * unit_cost), 2) as gross_purchase_value
from target.fact_purchase_order
group by order_status
order by purchase_order_count desc;

\echo ''
\echo '10. Shipments by status'
\echo '------------------------------------------------------------'

select
    shipment_status,
    count(*) as shipment_count,
    sum(quantity_shipped) as total_quantity_shipped
from target.fact_shipment
group by shipment_status
order by shipment_count desc;

\echo ''
\echo '11. Inventory movement summary by event type'
\echo '------------------------------------------------------------'

select
    event_type,
    count(*) as movement_count,
    sum(quantity_change) as net_quantity_change
from target.fact_inventory_movement
group by event_type
order by movement_count desc;

\echo ''
\echo '12. Inventory snapshot summary'
\echo '------------------------------------------------------------'

select
    count(*) as snapshot_rows,
    count(distinct product_id) as distinct_products,
    count(distinct location_id) as distinct_locations,
    sum(on_hand_quantity) as total_on_hand_quantity
from target.fact_inventory_snapshot;

\echo ''
\echo '13. Top inventory positions'
\echo '------------------------------------------------------------'

select
    product_id,
    location_id,
    on_hand_quantity,
    last_event_timestamp
from target.fact_inventory_snapshot
order by on_hand_quantity desc
limit 10;

\echo ''
\echo '14. Duplicate event handling evidence'
\echo '------------------------------------------------------------'

select
    entity_name,
    rejection_stage,
    rejection_reason,
    count(*) as duplicate_rejection_count
from monitoring.rejected_records
where rejection_stage = 'EVENT_DEDUPLICATION'
group by
    entity_name,
    rejection_stage,
    rejection_reason;

\echo ''
\echo '15. NiFi PostgreSQL connectivity test'
\echo '------------------------------------------------------------'

select
    test_name,
    test_status,
    details,
    created_at
from monitoring.nifi_connectivity_test
order by created_at desc
limit 5;

\echo ''
\echo '16. NiFi flat-file ingestion demo count'
\echo '------------------------------------------------------------'

select
    count(*) as nifi_loaded_products
from raw.nifi_products_file_raw;

\echo ''
\echo '17. NiFi API ingestion demo count'
\echo '------------------------------------------------------------'

select
    count(*) as nifi_loaded_sales_orders
from raw.nifi_sales_orders_api_raw;

\echo ''
\echo '18. NiFi API ingestion sample'
\echo '------------------------------------------------------------'

select
    sales_order_id,
    sales_order_line_id,
    product_id,
    location_id,
    order_status,
    quantity_ordered,
    unit_price,
    ingested_by,
    ingested_at
from raw.nifi_sales_orders_api_raw
order by ingested_at desc
limit 10;

\echo ''
\echo '============================================================'
\echo 'END OF DEMO QUERIES'
\echo '============================================================'
\echo ''