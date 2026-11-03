-- The defects on the live definitions (before the migration), and the old gap selection recorded for comparison.
set client_min_messages = notice;

-- the catalogue the gap queue reads: 3 providers (one hidden), 300 active courses and 20 withdrawn, items in every state the rules name
insert into catalogue.providers(id, canonical_name, address_line1, lifecycle_status) values
 ('00000000-0000-0000-0000-0000000000a1', 'Alpha University', null, 'active'), ('00000000-0000-0000-0000-0000000000a2', 'Beta Institute', '1 Main St', 'active'),
 ('00000000-0000-0000-0000-0000000000a3', 'Hidden College', null, 'hidden');
insert into catalogue.courses(id, provider_id, canonical_title, lifecycle_status, duration_value, study_level_id)
select md5('course' || g)::uuid, (array['00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a3'])[1 + g % 3]::uuid,
       'Course ' || g, case when g > 300 then 'withdrawn' else 'active' end, case when g % 4 = 0 then 2 end, case when g % 5 = 0 then gen_random_uuid() end
  from generate_series(1, 320) g;
insert into catalogue.course_intakes select md5('course' || g)::uuid, 'active' from generate_series(1, 320, 7) g;
insert into pipeline.admin_jobs(id, kind, state, title, requested_by, reason) values ('00000000-0000-0000-0000-00000000f001', 'enrich_fields', 'done', 'old', gen_random_uuid(), 'old task');
-- filled and since emptied (taken again), queued (not taken), skipped recently (not taken), skipped long ago (taken), page read since (taken)
insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state, updated_at)
select '00000000-0000-0000-0000-00000000f001', c.provider_id, c.id, 'duration', (array['filled', 'queued', 'skipped', 'skipped', 'not_stated'])[1 + n % 5],
       case when n % 5 = 3 then now() - interval '90 days' when n % 5 = 4 then now() - interval '2 days' else now() - interval '1 day' end
  from (select c.*, row_number() over (order by c.id) n from catalogue.courses c where c.duration_value is null and c.lifecycle_status = 'active') c where c.n <= 60;
-- course pages: most courses have a proven page (bound, read with an identity proof, stored); every sixth has none, every eleventh a page the
-- course page check refuses, every thirteenth a page not read with a proof (E16)
insert into pipeline.evidence_artifacts(id, storage_path) select md5('ev' || c.id)::uuid, 'layer2/AU/coverage/' || c.id || '.html.gz' from catalogue.courses c;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, read_at, read_status, identity_basis, evidence_id, candidates)
select c.id, c.provider_id, 'https://p.example/' || case when c.n % 11 = 0 then 'refuse/' else '' end || c.n, 'bound', now() - interval '30 days',
       'read', case when c.n % 13 = 0 then null else 'cricos_code' end, md5('ev' || c.id)::uuid, '{}'::jsonb
  from (select c.*, row_number() over (order by c.id) n from catalogue.courses c) c where c.n % 6 <> 0;
insert into pipeline.coverage_course_pages(course_id, provider_id, read_at)
select e.course_id, e.provider_id, now() from pipeline.field_enrich_items e where e.state = 'not_stated'
on conflict (course_id) do update set read_at = excluded.read_at;
insert into pipeline.manual_locks(entity, entity_id, field) select 'course', c.id, 'level' from catalogue.courses c order by c.id limit 5;

-- the old single statement (live tick) selects this set; it is kept to compare with the new slices
do $$
declare v jsonb;
begin
  v := security.field_gap_queue_tick_v1();
  raise notice 'before, live tick: %', v - 'crosscheck';
  create table public.fx_old_set as select e.provider_id, e.course_id, e.field from pipeline.field_enrich_items e where e.job_id = (v->>'job_id')::uuid;
  raise notice 'before, live tick selected % items (% courses)', (select count(*) from public.fx_old_set), (select count(distinct course_id) from public.fx_old_set);
  -- what the reader would skip at once (E16): page-only fields (duration, intakes) of courses with no proven page
  create table public.fx_old_unproven as select o.* from public.fx_old_set o where o.field in ('duration', 'intakes')
     and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = o.course_id and g.read_status = 'read' and g.identity_basis is not null and g.evidence_id is not null and g.url not like '%refuse%');
  create table public.fx_expect as select * from public.fx_old_set except select * from public.fx_old_unproven;
  raise notice 'before, of those % would be skipped by the reader as no proven course page (E16)', (select count(*) from public.fx_old_unproven);
  -- reset: the fixture task and its items are removed so the new run starts from the same state
  delete from pipeline.field_enrich_items where job_id = (v->>'job_id')::uuid;
  delete from pipeline.admin_job_events where job_id = (v->>'job_id')::uuid;
  delete from pipeline.admin_jobs where id = (v->>'job_id')::uuid;
end $$;

-- D1: the worker report fails on scholarship_read's answer ("applied": []), so none of its calls is recorded
do $$
begin
  perform public.svc_worker_report_v1('scholarship_read', 200, 3548, '{"ok":true,"mode":"scholarship_read","items":0,"tally":{},"applied":[],"readVia":"scraper"}'::jsonb, 'w');
  raise exception 'before D1: expected the report to fail';
exception when invalid_text_representation then
  raise notice 'before D1 reproduced: scholarship_read report fails (%), no ledger row', sqlerrm;
end $$;

-- D2: with the scholarship share spent, the AI picker leases items with no stored copy ahead of the stored one
insert into pipeline.coverage_vendor_usage(units, purpose) values (100, 'sch_scrape');
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, url) values ('m1', 1, 'admit', 'https://a.example/1'), ('m1', 1, 'admit', 'https://a.example/2');
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, url, storage_path) values ('m1', 1, 'admit', 'https://a.example/3', 'layer2/AU/s/3.html.gz');
do $$
declare v jsonb := public.svc_scholarship_ai_next(2);
begin
  if (select array_agg((x->>'url') order by x->>'url') from jsonb_array_elements(v) x) <> array['https://a.example/1', 'https://a.example/2'] then raise exception 'before D2: %', v; end if;
  raise notice 'before D2 reproduced: budget held, picker took the two items with no stored copy (each uses a try), the stored item waited';
  update pipeline.scholarship_ai_queue set state = 'queued', leased_until = null, attempts = 0;
end $$;

-- D3: the re-check picker leases a review with no stored copy while the scholarship lane is held
insert into pipeline.scholarship_ai_reviews(url, storage_path, recheck) values ('https://a.example/r1', null, '{"state":"queued"}'), ('https://a.example/r2', 'layer2/AU/r2.html.gz', '{"state":"queued"}');
do $$
declare v jsonb := public.svc_scholarship_recheck_next(1);
begin
  if v->0->>'url' <> 'https://a.example/r1' then raise exception 'before D3: %', v; end if;
  raise notice 'before D3 reproduced: the review with no stored copy is re-checked while held (recorded "could not be read again")';
  update pipeline.scholarship_ai_reviews set recheck = '{"state":"queued"}';
end $$;

-- D4 (IQ-00060): the live flag recheck switches the jobs paused by the governed restore on again for a "trial run"
do $$
declare v jsonb := security.flag_jobs_v1();
begin
  if not (select bool_and(active) from cron.job where jobname in ('coverage-discover', 'coverage-discover-2', 'central-find')) then raise exception 'before D4: %', v; end if;
  raise notice 'before D4 reproduced: flag recheck switched on coverage-discover and coverage-discover-2 (paused by event #28683) and central-find: %', v;
  -- back to the state the restore left: off, idle flag raised and due
  update cron.job set active = false where jobname in ('coverage-discover', 'coverage-discover-2', 'central-find');
  update pipeline.enrichment_flags set state = 'raised', released_at = null, next_check_at = now() - interval '1 minute' where entity = 'job';
end $$;
