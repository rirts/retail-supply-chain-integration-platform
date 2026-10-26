-- Transactional regression checks; production/demo contents are restored by ROLLBACK.
begin;
do $$
declare b uuid; accepted integer; rejected integer; good jsonb;
begin
    if monitoring.try_integer('abc') is not null then raise exception 'unsafe integer parser'; end if;
    if monitoring.try_integer('99999999999999999999') is not null then raise exception 'integer overflow not handled'; end if;
    if monitoring.try_timestamptz('not-a-date') is not null then raise exception 'unsafe timestamp parser'; end if;
    if monitoring.try_numeric('99999999999999999999999') is not null then raise exception 'numeric overflow not handled'; end if;
    select raw_payload into good from raw.inventory_events_raw
    where raw_payload->>'event_id' is not null
      and monitoring.try_integer(raw_payload->>'quantity_change') is not null
      and monitoring.try_timestamptz(raw_payload->>'event_timestamp') is not null
      and exists(select 1 from target.dim_product where product_id=raw_payload->>'product_id')
      and exists(select 1 from target.dim_location where location_id=raw_payload->>'location_id') limit 1;
    if good is null then raise exception 'Run the demo before regression tests'; end if;
    insert into monitoring.batch_audit_log(pipeline_name,source_system,entity_name,batch_type,source_count,status)
    values('regression','regression','inventory_events','EVENT_STREAM',3,'RAW_LOADED') returning batch_id into b;
    insert into raw.inventory_events_raw(event_id,batch_id,raw_payload) values
      ('REG-GOOD',b,good||jsonb_build_object('event_id','REG-GOOD')),
      ('REG-QTY',b,good||jsonb_build_object('event_id','REG-QTY','quantity_change','abc')),
      ('REG-DATE',b,good||jsonb_build_object('event_id','REG-DATE','event_timestamp','not-a-date'));
    select result_accepted_count,result_rejected_count into accepted,rejected
    from monitoring.validate_inventory_event_batch(b);
    if accepted<>1 or rejected<>2 then raise exception 'Expected 1 accepted and 2 rejected, got %/%',accepted,rejected; end if;
end;
$$;
rollback;
