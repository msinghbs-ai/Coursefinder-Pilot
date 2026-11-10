-- HELD (not a migration): forward recovery for 20261110141000 (the Basic -> Enriched upgrade lane is gated on its own queue). Run only if the Platform Admin decides to go back to the earlier text.
-- It puts back the text of security.provider_description_enqueue_v1 before that migration, byte for byte (body md5 e97170e51cb27dee62db0cef3e07bb43), guarded by the md5 of what is live now: it stops, and changes nothing, if the live body is neither
-- its earlier text nor the one the migration wrote (6506620f2895f0b977e40261f4ff6afd). Reads already queued, descriptions and settings are never touched. After it the upgrade lane runs only while fewer than pdesc.queue_cap reads of any kind wait. The migration applies again after it.
do $g$
declare v_e text;
begin
  select md5(p.prosrc) into v_e from pg_proc p where p.oid = to_regprocedure('security.provider_description_enqueue_v1()');
  if v_e is null then raise exception 'the provider-description enqueue is missing'; end if;
  if v_e not in ('e97170e51cb27dee62db0cef3e07bb43', '6506620f2895f0b977e40261f4ff6afd') then raise exception 'live security.provider_description_enqueue_v1 differs from both texts this recovery knows (body md5 %)', v_e; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.provider_description_enqueue_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
-- provider-description-autonomy-v1
 declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb;
begin
 if security.pipeline_num_v1('pdesc.enabled',0)<1 then return 0; end if;
 if security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 then
  -- automatic mode: each country is its own bounded queue, sized from the providers still to do and the observed rate; each looks at a bounded slice (QA B2)
  v_n:=0; v_t:=security.provider_description_throughput_v1();
  for v_cc,v_share in select e.key,e.value::int from jsonb_each_text(coalesce(v_t->'share','{}'::jsonb)) e order by e.key loop
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',v_share,'country',v_cc,'prefilter',true,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end));
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(v_sel->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
   -- the providers looked at that cannot be read yet, and those returned, go to the back of the rotation
   insert into pipeline.provider_description_scan_marks(provider_id,scanned_at,last_reason)
   select u.pid::uuid,now(),'looked at' from (select jsonb_array_elements_text(coalesce(v_sel->'scanned','[]'::jsonb)) pid union select y->>'provider_id' from jsonb_array_elements(coalesce(v_sel->'providers','[]'::jsonb)) y) u
   on conflict (provider_id) do update set scanned_at=excluded.scanned_at,last_reason=excluded.last_reason;
  end loop;
  -- register-fact profiles with a page to read (pdesc.registry_upgrade_on): after the providers with no description, a bounded number a run
  -- the upgrade lane is bounded by existing settings: pdesc.queue_per_run a run, and none while pdesc.queue_cap or more reads already wait (the providers with no description come first)
  if security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and (select count(*) from pipeline.provider_description_reads q where q.state='queued')<security.pipeline_num_v1('pdesc.queue_cap',60) then
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int,'prefilter',true,'upgrade',true,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end));
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(v_sel->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
   insert into pipeline.provider_description_scan_marks(provider_id,scanned_at,last_reason)
   select u.pid::uuid,now(),'looked at' from (select jsonb_array_elements_text(coalesce(v_sel->'scanned','[]'::jsonb)) pid union select y->>'provider_id' from jsonb_array_elements(coalesce(v_sel->'providers','[]'::jsonb)) y) u
   on conflict (provider_id) do update set scanned_at=excluded.scanned_at,last_reason=excluded.last_reason;
  end if;
  return v_n;
 end if;
 insert into pipeline.provider_description_reads(provider_id)
 select (x->>'provider_id')::uuid from jsonb_array_elements(security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.pending_max',10),security.pipeline_num_v1('run_now.pilot_cap',20))::int,
 'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end))->'providers') x
 where (x->>'eligible')::boolean on conflict do nothing;
 get diagnostics v_n=row_count; return v_n;
end $body$;

do $c$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.provider_description_enqueue_v1()'::regprocedure) <> 'e97170e51cb27dee62db0cef3e07bb43' then raise exception 'the enqueue was not restored byte for byte'; end if;
end $c$;
