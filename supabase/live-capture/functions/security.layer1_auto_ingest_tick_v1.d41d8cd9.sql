CREATE OR REPLACE FUNCTION security.layer1_auto_ingest_tick_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare rec record; v_queued int:=0; v_skipped jsonb:='[]'::jsonb; v_run jsonb;
begin
  for rec in
    select o.source_id, o.variance_decision, o.last_source_hash, o.previous_accepted_hash
      from pipeline.layer1_source_operations o
     where o.auto_ingest and o.active and not o.paused
       and o.last_source_hash is not null and o.last_source_hash is distinct from o.previous_accepted_hash
       and coalesce(o.verification_status,'') in ('passed','warning')
       and (o.next_verification_at is null or o.next_verification_at>now())
       and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id=o.source_id and q.status in ('queued','running'))
       -- do not retry a hash that an automatic run already failed on; a person decides
       and not exists (select 1 from pipeline.layer1_run_queue q where q.source_id=o.source_id and q.source_hash=o.last_source_hash
                         and q.status in ('failed','blocked') and q.requested_by='c0ffee00-0000-4000-8000-000000000150')
  loop
    if rec.variance_decision is distinct from 'pass' then
      v_skipped:=v_skipped||jsonb_build_object('source_id',rec.source_id,'reason','variance '||coalesce(rec.variance_decision,'unknown'));
      continue;
    end if;
    v_run:=security.layer1_queue_system_run_v1(rec.source_id,'apply',0,null,'Automatic ingestion: the register changed and the record count is within the pass band');
    v_queued:=v_queued+1;
  end loop;
  return jsonb_build_object('queued',v_queued,'skipped',v_skipped,'at',now());
end $function$
