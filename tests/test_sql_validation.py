"""Integration contracts; CI uses an isolated PostgreSQL 16 database."""
import json
import os
from pathlib import Path
import psycopg
import pytest

pytestmark = pytest.mark.skipif(not os.getenv("PG_TEST_DSN"), reason="PG_TEST_DSN not configured")
ROOT = Path(__file__).resolve().parents[1]

@pytest.fixture
def connection():
    with psycopg.connect(os.environ["PG_TEST_DSN"]) as conn:
        for file in sorted((ROOT / "sql").glob("*.sql")):
            if file.name.startswith(("07_", "17_", "18_")):
                continue
            conn.execute(file.read_text())
        conn.commit()
        conn.execute("insert into target.dim_supplier(supplier_id,supplier_name,country_code,supplier_status,source_system) values('REG-S','Supplier','MX','ACTIVE','test')")
        conn.execute("insert into target.dim_product(product_id,sku,product_name,category,supplier_id,unit_cost,product_status,source_system) values('REG-P','REG-SKU','Product','demo','REG-S',10,'ACTIVE','test')")
        conn.execute("insert into target.dim_location(location_id,location_name,location_type,region,country_code,location_status,source_system) values('REG-L','Location','STORE','central','MX','ACTIVE','test')")
        conn.execute("insert into staging.stg_suppliers(batch_id,supplier_id,source_system,record_status) values(gen_random_uuid(),'REG-S','test','ACCEPTED')")
        yield conn
        conn.rollback()

def batch(conn, entity, kind, count):
    return conn.execute("insert into monitoring.batch_audit_log(pipeline_name,source_system,entity_name,batch_type,source_count,status) values('test','test',%s,%s,%s,'RAW_LOADED') returning batch_id", (entity,kind,count)).fetchone()[0]

def test_malformed_events_are_quarantined(connection):
    c = connection
    good = dict(event_id='REG-E',event_type='INVENTORY_RECEIVED',product_id='REG-P',location_id='REG-L',quantity_change=10,reason_code='PURCHASE_ORDER_RECEIPT',event_timestamp='2026-07-01T00:00:00Z',published_at='2026-07-01T01:00:00Z')
    data = [good,{**good,'event_id':'REG-Q','quantity_change':'abc'},{**good,'event_id':'REG-D','event_timestamp':'not-a-date'},{}]
    b = batch(c,'inventory_events','EVENT_STREAM',len(data))
    for row in data:
        c.execute('insert into raw.inventory_events_raw(event_id,batch_id,raw_payload) values(%s,%s,%s)',(row.get('event_id'),b,json.dumps(row)))
    result = c.execute('select * from monitoring.validate_inventory_event_batch(%s)',(b,)).fetchone()
    assert result[3:5] == (1,3)
    loaded = c.execute('select * from target.load_validated_inventory_event_batch(%s)',(b,)).fetchone()
    assert loaded[5] == 1
    assert c.execute("select on_hand_quantity from target.fact_inventory_snapshot where product_id='REG-P'").fetchone()[0] == 10

def test_cross_batch_sku_is_rejected(connection):
    c = connection
    b = batch(c,'products','FLAT_FILE',1)
    value=dict(product_id='REG-OTHER',sku='REG-SKU',product_name='Other',category='demo',supplier_id='REG-S',unit_cost='20',product_status='ACTIVE')
    c.execute("insert into raw.file_ingestion_raw(batch_id,source_system,entity_name,raw_payload) values(%s,'test','products',%s)",(b,json.dumps(value)))
    result=c.execute('select * from monitoring.validate_flat_file_master_data_batch(%s)',(b,)).fetchone()
    assert result[3:5] == (0,1)


def test_safe_conversions_reject_nonfinite_and_overflow(connection):
    c = connection
    assert c.execute("select monitoring.try_numeric('NaN'), monitoring.try_numeric('1e1000'), monitoring.try_integer('999999999999999999999'), monitoring.try_timestamptz('infinity')").fetchone() == (None, None, None, None)
