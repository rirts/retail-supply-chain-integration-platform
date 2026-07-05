\pset pager off

\echo ''
\echo '============================================================'
\echo 'FINAL VALIDATION CHECKS'
\echo '============================================================'
\echo ''

\echo '1. Expected target counts'
\echo '------------------------------------------------------------'

with expected_counts as (
    select 'target.dim_supplier' as table_name, 24 as expected_count
    union all select 'target.dim_product', 233
    union all select 'target.dim_location', 49
    union all select 'target.fact_sales_order', 280
    union all select 'target.fact_purchase_order', 136
    union all select 'target.fact_shipment', 164
    union all select 'target.fact_inventory_movement', 187
    union all select 'target.fact_inventory_snapshot', 182
),
actual_counts as (
    select 'target.dim_supplier' as table_name, count(*) as actual_count from target.dim_supplier
    union all select 'target.dim_product', count(*) from target.dim_product
    union all select 'target.dim_location', count(*) from target.dim_location
    union all select 'target.fact_sales_order', count(*) from target.fact_sales_order
    union all select 'target.fact_purchase_order', count(*) from target.fact_purchase_order
    union all select 'target.fact_shipment', count(*) from target.fact_shipment
    union all select 'target.fact_inventory_movement', count(*) from target.fact_inventory_movement
    union all select 'target.fact_inventory_snapshot', count(*) from target.fact_inventory_snapshot
)
select
    e.table_name,
    e.expected_count,
    a.actual_count,
    case
        when e.expected_count = a.actual_count then 'PASS'
        else 'FAIL'
    end as check_status
from expected_counts e
join actual_counts a
    on e.table_name = a.table_name
order by e.table_name;

\echo ''
\echo '2. Reconciliation checks'
\echo '------------------------------------------------------------'

select
    entity_name,
    source_count,
    accepted_count,
    rejected_count,
    loaded_count,
    count_difference,
    status,
    case
        when source_count = accepted_count + rejected_count
         and accepted_count = loaded_count
         and count_difference = 0
         and status in ('MATCHED', 'MATCHED_WITH_REJECTIONS')
        then 'PASS'
        else 'FAIL'
    end as check_status
from monitoring.reconciliation_results
order by reconciled_at desc;

\echo ''
\echo '3. NiFi demo checks'
\echo '------------------------------------------------------------'

select
    'nifi_products_file_raw' as check_name,
    255 as expected_count,
    count(*) as actual_count,
    case when count(*) = 255 then 'PASS' else 'FAIL' end as check_status
from raw.nifi_products_file_raw
union all
select
    'nifi_sales_orders_api_raw',
    25,
    count(*),
    case when count(*) = 25 then 'PASS' else 'FAIL' end
from raw.nifi_sales_orders_api_raw;

\echo ''
\echo '4. NiFi connectivity check'
\echo '------------------------------------------------------------'

select
    test_name,
    test_status,
    case
        when test_status = 'PASSED' then 'PASS'
        else 'FAIL'
    end as check_status,
    created_at
from monitoring.nifi_connectivity_test
order by created_at desc
limit 1;

\echo ''
\echo '5. Duplicate event handling check'
\echo '------------------------------------------------------------'

select
    'event_deduplication_rejection_exists' as check_name,
    count(*) as duplicate_rejection_count,
    case
        when count(*) >= 1 then 'PASS'
        else 'FAIL'
    end as check_status
from monitoring.rejected_records
where rejection_stage = 'EVENT_DEDUPLICATION';

\echo ''
\echo '============================================================'
\echo 'END OF FINAL VALIDATION CHECKS'
\echo '============================================================'
\echo ''