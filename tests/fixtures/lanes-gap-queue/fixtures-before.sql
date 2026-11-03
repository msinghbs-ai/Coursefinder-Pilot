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
insert into pipeline.coverage_course_pages(course_id, provider_id, read_at)
select e.course_id, e.provider_id, now() from pipeline.field_enrich_items e where e.state = 'not_stated';
insert into pipeline.manual_locks(entity, entity_id, field) select 'course', c.id, 'level' from catalogue.courses c order by c.id limit 5;

-- the old single statement (live tick) selects this set; it is kept to compare with the new slices
do $$
declare v jsonb;
begin
  v := security.field_gap_queue_tick_v1();
  raise notice 'before, live tick: %', v - 'crosscheck';
  create table public.fx_old_set as select e.provider_id, e.course_id, e.field from pipeline.field_enrich_items e where e.job_id = (v->>'job_id')::uuid;
  raise notice 'before, live tick selected % items (% courses)', (select count(*) from public.fx_old_set), (select count(distinct course_id) from public.fx_old_set);
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
