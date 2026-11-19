CREATE OR REPLACE FUNCTION security.provider_description_enqueue_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- provider-description-autonomy-v1
 declare v_n int; v_k int; v_t jsonb; v_cc text; v_share int; v_sel jsonb; v_up int;
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
  -- the upgrade lane has its OWN bound: the queued reads of providers that hold a register-fact profile are counted against the lower of pdesc.queue_per_run and pdesc.queue_cap, and the lane tops them up to that bound each run, however many reads of providers with no description wait (they used to switch the lane off, so an upgrade was never queued)
  v_up:=case when security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 then (select count(*) from pipeline.provider_description_reads q where q.state='queued' and security.provider_description_basic_profile_v1(q.provider_id) is not null) end;
  if v_up is not null and v_up<least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60)) then
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int-v_up,'prefilter',true,'upgrade',true,
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
end $function$
