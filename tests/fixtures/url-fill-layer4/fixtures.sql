-- Course link fill respects Layer 4: the cases. Each block raises on a wrong result and prints "ok <case>".
\set ON_ERROR_STOP 1
-- an NZ provider and five courses whose pages are proven (bound, read, stored copy)
insert into ref.countries(id, iso_alpha2) values ('00000000-0000-0000-0000-0000000000aa', 'NZ');
insert into catalogue.providers(id, country_id) values ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000aa');
insert into catalogue.courses(id, provider_id) select ('00000000-0000-0000-0000-00000000000' || n)::uuid, '00000000-0000-0000-0000-0000000000bb' from generate_series(1, 5) n;
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, read_status, evidence_id)
  select ('00000000-0000-0000-0000-00000000000' || n)::uuid, '00000000-0000-0000-0000-0000000000bb', 'https://nz.example/c' || n, 'bound', 'adapter_title', 'read', gen_random_uuid()
    from generate_series(1, 5) n;
-- course 2: a pending course-link review; course 3: a pending review of another field; course 4: a decided course-link review only
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value) values
  ('course', '00000000-0000-0000-0000-000000000002', 'official_course_url', 'pending', '{"course_url":"https://nz.example/other"}'),
  ('course', '00000000-0000-0000-0000-000000000003', 'provider_current_tuition_validation', 'pending', '{"amount":1}'),
  ('course', '00000000-0000-0000-0000-000000000004', 'official_course_url', 'approved', '{"course_url":"https://nz.example/c4"}');
-- course 5: pending course-link review too
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value) values
  ('course', '00000000-0000-0000-0000-000000000005', 'official_course_url', 'pending', '{"course_url":"https://nz.example/c5"}');

-- 1 the switch on (default): courses 2 and 5 are left and counted; 1, 3, 4 are filled; no integration queue yet
do $c$ declare r jsonb; e jsonb; begin
  r := security.course_url_fill_v1();
  if (r->>'filled')::int <> 3 or (r->>'skipped_pending_layer4')::int <> 2 or (r->>'respects_layer4')::boolean is not true or r->'integration_queue' <> 'null'::jsonb then
    raise exception 'case 1: %', r; end if;
  if exists (select 1 from catalogue.courses where id in ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000005') and course_url is not null) then
    raise exception 'case 1: a course with a pending review was filled'; end if;
  if (select count(*) from catalogue.courses where course_url is not null) <> 3 then raise exception 'case 1: filled count'; end if;
  select detail into e from pipeline.admin_control_events where action = 'course_url_filled' order by id desc limit 1;
  if (e->>'skipped_pending_layer4')::int <> 2 or (e->>'filled')::int <> 3 then raise exception 'case 1 event: %', e; end if;
  raise notice 'ok 1 pending course-link review left and counted (filled 3, skipped 2; other field and decided review filled)';
end $c$;

-- 2 a run with nothing to fill but skips still writes its event (skips are visible)
do $c$ declare r jsonb; n int; begin
  select count(*) into n from pipeline.admin_control_events where action = 'course_url_filled';
  r := security.course_url_fill_v1();
  if (r->>'filled')::int <> 0 or (r->>'skipped_pending_layer4')::int <> 2 then raise exception 'case 2: %', r; end if;
  if (select count(*) from pipeline.admin_control_events where action = 'course_url_filled') <> n + 1 then raise exception 'case 2: no event for a skip-only run'; end if;
  raise notice 'ok 2 skip-only run is recorded in its event';
end $c$;

-- 3 the integration queue exists: one issue by fingerprint, an unchanged problem updates it (no duplicate)
create table pipeline.integration_issues (id bigserial primary key, fingerprint text unique, payload jsonb, actor text, observed int default 1);
create function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $f$
begin
  insert into pipeline.integration_issues(fingerprint, payload, actor) values (p->>'fingerprint', p, p_actor)
  on conflict (fingerprint) do update set observed = pipeline.integration_issues.observed + 1, payload = excluded.payload;
  return jsonb_build_object('action', 'upserted', 'fingerprint', p->>'fingerprint');
end $f$;
do $c$ declare r jsonb; begin
  r := security.course_url_fill_v1();
  r := security.course_url_fill_v1();
  if (select count(*) from pipeline.integration_issues) <> 1 then raise exception 'case 3: % issues', (select count(*) from pipeline.integration_issues); end if;
  if (select observed from pipeline.integration_issues) <> 2 then raise exception 'case 3: not updated in place'; end if;
  if (select payload->>'fingerprint' from pipeline.integration_issues) <> 'course-url-fill:skipped-pending-layer4'
     or (select payload->>'workstream' from pipeline.integration_issues) <> 'A4'
     or (select jsonb_array_length(payload->'course_ids') from pipeline.integration_issues) <> 2
     or (select actor from pipeline.integration_issues) <> 'course-url-fill' then raise exception 'case 3: payload %', (select payload from pipeline.integration_issues); end if;
  if r->'integration_queue'->>'fingerprint' <> 'course-url-fill:skipped-pending-layer4' then raise exception 'case 3: %', r; end if;
  raise notice 'ok 3 one integration-queue issue by fingerprint, updated in place on the next run';
end $c$;

-- 4 a queue error never stops the fill
create or replace function security.integration_issue_upsert_v1(p jsonb, p_actor text default 'integration-validate') returns jsonb language plpgsql as $f$
begin raise exception 'queue unavailable'; end $f$;
insert into catalogue.courses(id, provider_id) values ('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-0000000000bb');
insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis, read_status, evidence_id)
  values ('00000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-0000000000bb', 'https://nz.example/c6', 'bound', 'adapter_title', 'read', gen_random_uuid());
do $c$ declare r jsonb; begin
  r := security.course_url_fill_v1();
  if (r->>'filled')::int <> 1 or r->'integration_queue'->>'error' not like '%queue unavailable%' then raise exception 'case 4: %', r; end if;
  raise notice 'ok 4 queue error recorded, fill completed (filled 1)';
end $c$;

-- 5 the switch off: the old behaviour (courses 2 and 5 filled, nothing skipped)
update pipeline.platform_toolset_settings set value = '0' where key = 'course_url.fill_respects_layer4';
do $c$ declare r jsonb; begin
  r := security.course_url_fill_v1();
  if (r->>'filled')::int <> 2 or (r->>'skipped_pending_layer4')::int <> 0 or (r->>'respects_layer4')::boolean is not false then raise exception 'case 5: %', r; end if;
  raise notice 'ok 5 switch off: the old behaviour (filled 2, skipped 0)';
end $c$;

-- 6 the pause threshold is the setting course_url.retraction_min_fills (was the number 50)
update pipeline.fx_rate set filled = 40, retraction_pct = 50;
do $c$ declare r jsonb; begin
  r := security.course_url_fill_v1();
  if r ? 'paused' then raise exception 'case 6a: paused below the default threshold: %', r; end if;
  update pipeline.platform_toolset_settings set value = '30' where key = 'course_url.retraction_min_fills';
  r := security.course_url_fill_v1();
  if not r ? 'paused' then raise exception 'case 6b: not paused at the lowered threshold: %', r; end if;
  if (select value from pipeline.platform_toolset_settings where key = 'course_url.fill_enabled') <> '0'::jsonb then raise exception 'case 6b: fill_enabled not switched off'; end if;
  raise notice 'ok 6 pause threshold read from course_url.retraction_min_fills (40 fills: no pause at 50, pause at 30)';
end $c$;

-- 7 settings: labelled, ranged, used_by stated (G2)
do $c$ begin
  if (select count(*) from pipeline.platform_toolset_settings where key in ('course_url.fill_respects_layer4', 'course_url.retraction_min_fills')
        and label is not null and min_value is not null and max_value is not null and unit is not null and used_by like '%course_url_fill_v1%') <> 2 then
    raise exception 'case 7: settings incomplete'; end if;
  if (select count(*) from pipeline.automation_catalogue where jobname = 'course-url-fill' and description like '%Official link: wait for Layer 4%') <> 1 then raise exception 'case 7: catalogue note'; end if;
  raise notice 'ok 7 two settings with label, range, unit and used_by; catalogue note says the rule';
end $c$;
