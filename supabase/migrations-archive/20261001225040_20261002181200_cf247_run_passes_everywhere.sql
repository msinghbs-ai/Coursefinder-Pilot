-- CF-247 (Decision 216, 2 Oct 2026). Platform Admin chose to move every background function off the long-lived automation
-- key (expired 30 Sep 2026) to one-time run passes. One allow-list (pipeline.pilot_nonce_functions) now governs which
-- functions may be given a pass. public.svc_pilot_issue_nonce gives a pass to the service role (edge functions that call
-- another function mint a fresh pass for each call). The five database callers that sent the key now send a pass.
-- Every function patch is behind an md5 guard on its current source.

create table if not exists pipeline.pilot_nonce_functions (
  function_name text primary key,
  added_at timestamptz not null default now(),
  note text
);
alter table pipeline.pilot_nonce_functions enable row level security;
revoke all on pipeline.pilot_nonce_functions from public, anon, authenticated;

insert into pipeline.pilot_nonce_functions(function_name, note)
select f, 'run passes before Decision 216' from unnest(array[
  'layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness','coursefacts-au-rmit',
  'coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled','layer1-operations-control',
  'evidence-storage-dedupe','ranking-publisher-control','statistics-edition-discovery','fee-schedule-etl','coverage-sweep',
  'layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark','layer3-contact-benchmark',
  'layer2-screenshot-backfill-scheduled','provider-contact-discover-scheduled','provider-contact-enrich-apollo',
  'layer3-cf245-tuition-benchmark','layer3-work-dispatch','layer3-intake-benchmark','layer3-model-routing','evidence-link-index']) f
on conflict (function_name) do nothing;
insert into pipeline.pilot_nonce_functions(function_name, note)
select f, 'moved from the automation key (Decision 216)' from unnest(array[
  'layer1-ca-ab-alis-degrees','layer1-ca-algonquin-catalogue','layer1-ca-bc-epbc-programs','layer1-ca-cna-programs',
  'layer1-ca-conestoga-catalogue','layer1-ca-durham-programs','layer1-ca-fanshawe-pgwp','layer1-ca-firstparty-catalogues',
  'layer1-ca-mb-programs','layer1-ca-mohawk-catalogue','layer1-ca-ns-sk-programs','layer1-ca-on-college-programs',
  'layer1-ca-provider-geography','layer1-ca-qc-university-programs','layer1-ca-sk-programs','layer2-acquire-v2',
  'layer2-batch-runner','layer2-course-fact-extract-v2','layer2-extract-v2','layer2-hotcourses-directory-parse',
  'layer2-provider-asset-promote','layer2-provider-page-fanout','layer2-scholarship-catalogue-enumerate',
  'layer2-scholarship-extract','layer2-scholarship-extract-v2','layer2-v2-diagnostic','scholarship-scope-job-execute']) f
on conflict (function_name) do nothing;

-- a one-time pass (5 minutes) for an allow-listed function; service role only
create or replace function public.svc_pilot_issue_nonce(p_function text) returns uuid
language plpgsql security definer set search_path = '' as $fn$
declare v uuid := extensions.gen_random_uuid();
begin
  if not exists (select 1 from pipeline.pilot_nonce_functions f where f.function_name = p_function) then
    raise exception 'one-time Edge function is not allowlisted: %', p_function using errcode = '42501';
  end if;
  insert into pipeline.pilot_edge_nonces(id, function_name, expires_at) values (v, p_function, now() + interval '5 minutes');
  return v;
end $fn$;
revoke all on function public.svc_pilot_issue_nonce(text) from public, anon, authenticated;
grant execute on function public.svc_pilot_issue_nonce(text) to service_role;

-- patch the callers in place, each behind an md5 guard
do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('pipeline','svc_pilot_submit_nonce','c670c862016d2c3bfd242367b1229c9e',
      array[$o$if p_function not in('layer1-ca-niagara-catalogue','qilt-au-etl','prisms-au-etl','layer1-au-depth','layer1-au-completeness','coursefacts-au-rmit','coursefacts-au-uq','coursefacts-au-qut','layer1-au-cricos-facts','layer1-operations-scheduled','layer1-operations-control','evidence-storage-dedupe','ranking-publisher-control','statistics-edition-discovery','fee-schedule-etl','coverage-sweep','layer2-scope-discover-scheduled','layer2-scale-qualify-scheduled','layer3-source-pattern-benchmark','layer3-contact-benchmark','layer2-screenshot-backfill-scheduled','provider-contact-discover-scheduled','provider-contact-enrich-apollo','layer3-cf245-tuition-benchmark','layer3-work-dispatch','layer3-intake-benchmark','layer3-model-routing','evidence-link-index') then$o$],
      array[$n$if not exists(select 1 from pipeline.pilot_nonce_functions f where f.function_name=p_function) then$n$]),
    ('pipeline','svc_pilot_invoke_edge','9917b5203c5029ccd06dd1c2c7430c10',
      array[$o$v_key:=public.coursefinder_runtime_automation_key();$o$, $o$'x-cf-pilot-key',v_key$o$],
      array[$n$v_key:=public.svc_pilot_issue_nonce(p_function)::text;$n$, $n$'x-cf-run-nonce',v_key$n$]),
    ('pipeline','svc_pilot_invoke_layer2','a0868a29773268e3817d4d5a7d3013f1',
      array[$o$v_key:=public.coursefinder_runtime_automation_key();$o$, $o$'x-cf-pilot-key',v_key$o$],
      array[$n$v_key:=public.svc_pilot_issue_nonce(p_function)::text;$n$, $n$'x-cf-run-nonce',v_key$n$]),
    ('pipeline','svc_pilot_invoke_layer2_v2','0720356ac40709e9d813904b0d1c58c9',
      array[$o$v_key:=public.coursefinder_runtime_automation_key();$o$, $o$'x-cf-pilot-key',v_key$o$],
      array[$n$v_key:=public.svc_pilot_issue_nonce('layer2-acquire-v2')::text;$n$, $n$'x-cf-run-nonce',v_key$n$]),
    ('public','layer2_run_batch_dispatch','9a68ea0441fefb0450a07c26c24a0019',
      array[$o$v_key:=public.coursefinder_runtime_automation_key();$o$, $o$'x-cf-pilot-key',v_key$o$],
      array[$n$v_key:=public.svc_pilot_issue_nonce('layer2-batch-runner')::text;$n$, $n$'x-cf-run-nonce',v_key$n$]),
    ('pipeline','svc_invoke_evidence_link_index','7f8518e34cddce0235907ff2f5078990',
      array[$o$v_key := public.coursefinder_runtime_automation_key();$o$, $o$'x-cf-pilot-key',v_key$o$],
      array[$n$v_key := public.svc_pilot_issue_nonce('evidence-link-index')::text;$n$, $n$'x-cf-run-nonce',v_key$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;
