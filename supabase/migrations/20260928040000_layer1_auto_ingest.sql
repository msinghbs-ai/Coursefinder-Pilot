-- CF-247 / Decision 155 step 7: automatic register ingestion within the pass band.
-- When the weekly verification finds a changed register file and the record-count variance is
-- 'pass', an apply run is queued automatically under the system identity. The run applies only
-- new and changed records and retires departures (a large departure waits for a Platform Admin).
-- A 'warn' or 'block' variance, a paused or stale source, or a run already queued is left for a person.
-- Enabled for the CRICOS and NZQA registers. Consumer API: not touched.

alter table pipeline.layer1_source_operations add column if not exists auto_ingest boolean not null default false;
update pipeline.layer1_source_operations set auto_ingest=true
 where source_id in ('b5680d74-49c5-49a5-b198-a625f3e3fdcf','e410b159-614e-45ef-b8f4-902c7b516257') and not auto_ingest;

create or replace function security.layer1_auto_ingest_tick_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline','security' as $f$
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
end $f$;
revoke all on function security.layer1_auto_ingest_tick_v1() from public, anon, authenticated;

select cron.schedule('layer1-auto-ingest','34 * * * *','select security.layer1_auto_ingest_tick_v1();');

-- Show the setting on the Layer 1 card (checksum-guarded patch of the operations read).
do $patch$
declare v_def text:=pg_get_functiondef('security.admin_layer1_operations_read(jsonb)'::regprocedure);
begin
  if v_def like '%o.auto_ingest%' then return; end if;
  if md5(v_def)<>'5ec4c0924cfabcff5b564e0480a5e7ad' then raise exception 'admin_layer1_operations_read changed (md5 %); aborting', md5(v_def); end if;
  if (select count(*) from regexp_matches(v_def,'o\.verification_cadence_days,o\.ingestion_cadence_days,','g'))<>1 then raise exception 'read anchor not found exactly once'; end if;
  execute replace(v_def,'o.verification_cadence_days,o.ingestion_cadence_days,','o.verification_cadence_days,o.ingestion_cadence_days,o.auto_ingest,');
end $patch$;
