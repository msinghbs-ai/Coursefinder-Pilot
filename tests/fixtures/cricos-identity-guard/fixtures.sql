-- CF-247 D7 CRICOS identity guard: every case after the migration (seed.sql). Each block raises on failure and prints "<id> ok".

-- G1 shipped off: the switch is 0, the trigger runs after the E16 guard, and with it off a title binding on the proved page stands
do $f$
begin
  if security.pipeline_num_v1('binding.cricos_identity_guard_on', -1) <> 0 then raise exception 'G1: switch'; end if;
  if (select array_agg(tgname::text order by tgname) from pg_trigger where tgrelid = 'pipeline.coverage_course_pages'::regclass and not tgisinternal)
     <> array['coverage_page_refused_host', 'coverage_page_refused_host_zz_cricos'] then raise exception 'G1: trigger order'; end if;
  update pipeline.coverage_course_pages set identity_basis = 'title_level' where course_id = 'c0000000-0000-0000-0000-000000000001';
  update pipeline.coverage_course_pages set identity_basis = 'exact_title' where course_id = 'c0000000-0000-0000-0000-000000000001';
  if (select status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'bound' then raise exception 'G1: acted while off'; end if;
  raise notice 'G1 ok: ships off; runs after the E16 guard; with it off nothing changes';
end $f$;

-- G2 the conflict and the evaluation (read only): 088407E (same address, written with a slash) and the online page (same page text) would be
-- refused; the locked course and the unrelated page would not; one stored copy was read for another course
do $f$
declare c jsonb; r jsonb; v text := (select md5(string_agg(g::text, '|' order by g.course_id)) from pipeline.coverage_course_pages g);
begin
  c := security.cricos_identity_conflict_v1('c0000000-0000-0000-0000-000000000001', 'https://swinburne.edu.au/course/undergraduate/bict-professional/', null);
  if not (c->>'conflict')::boolean or c->'courses'->0->>'code' <> '095881J' or c->'courses'->0->>'how' <> 'same address' then raise exception 'G2: %', c; end if;
  if (security.cricos_identity_conflict_v1('c0000000-0000-0000-0000-000000000003', 'https://www.swinburne.edu.au/course/undergraduate/design', 'sha3')->>'conflict')::boolean then raise exception 'G2: unrelated'; end if;
  r := security.cricos_identity_guard_evaluate_v1(null);
  raise notice 'G2 %', r;
  if (r->'would_refuse'->>'bindings')::int <> 2 or r->'would_refuse'->'by_how'->>'same page text' <> '1'
     or (select count(*) from jsonb_array_elements(r->'would_refuse'->'sample') x where x->>'code' = '333333C') <> 0 then raise exception 'G2: evaluation'; end if;
  if (r->'shared_pages'->>'copies_read_for_another_course')::int <> 1 then raise exception 'G2: copies'; end if;
  if (select md5(string_agg(g::text, '|' order by g.course_id)) from pipeline.coverage_course_pages g) <> v then raise exception 'G2: the evaluation changed a binding'; end if;
  raise notice 'G2 ok: same address and same page text found; the locked course and the unrelated page left out; read only';
end $f$;

-- G3 switched on: a new title binding on the proved page and a re-read title binding are refused the way E16 refuses (recorded and routed);
-- a code-proved binding, a page set by hand, a course locked by hand and an unrelated change are not touched
do $f$
begin
  update pipeline.platform_toolset_settings set value = '1' where key = 'binding.cricos_identity_guard_on';
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, candidates)
  values ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional', 'title_search', 'bound', 'read', 'exact_title', '{}');
  if (select status || ':' || read_status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000006') <> 'mismatch:cricos_identity_refused' then raise exception 'G3: new binding'; end if;
  if not exists (select 1 from pipeline.page_rejections where course_id = 'c0000000-0000-0000-0000-000000000006' and reason like '%CRICOS code of another course (095881J)%') then raise exception 'G3: not recorded'; end if;
  if not exists (select 1 from pipeline.layer4_review_items where entity_id = 'c0000000-0000-0000-0000-000000000006' and field_code = 'official_course_url') then raise exception 'G3: not routed'; end if;
  update pipeline.coverage_course_pages set identity_basis = 'title_level' where course_id = 'c0000000-0000-0000-0000-000000000001';
  if (select status || ':' || read_status || ':' || coalesce(identity_basis, '-') from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000001') <> 'mismatch:cricos_identity_refused:-' then raise exception 'G3: re-read'; end if;
  update pipeline.coverage_course_pages set identity_basis = 'title_level' where course_id = 'c0000000-0000-0000-0000-000000000005';
  if (select status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000005') <> 'bound' then raise exception 'G3: a locked course was touched'; end if;
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, candidates)
  values ('c0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'https://www.swinburne.edu.au/course/undergraduate/bict-professional', 'manual', 'bound', null, 'exact_title', '{}');
  if (select status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000007') <> 'bound' then raise exception 'G3: a page set by hand was refused'; end if;
  update pipeline.coverage_course_pages set read_at = now() where course_id = 'c0000000-0000-0000-0000-000000000004';
  if (select status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000004') <> 'bound' then raise exception 'G3: an unrelated change was re-checked'; end if;
  update pipeline.coverage_course_pages set status = 'bound', identity_basis = 'cricos_code' where course_id = 'c0000000-0000-0000-0000-000000000002';
  if (select status from pipeline.coverage_course_pages where course_id = 'c0000000-0000-0000-0000-000000000002') <> 'bound' then raise exception 'G3: the proved course was touched'; end if;
  update pipeline.platform_toolset_settings set value = '0' where key = 'binding.cricos_identity_guard_on';
  raise notice 'G3 ok: on: new and re-read title bindings refused, recorded and routed; code-proved, by hand, locked and unrelated changes untouched';
end $f$;

-- G4 nothing deleted
do $f$
begin
  if (select count(*) from pipeline.coverage_course_pages) <> 7 then raise exception 'G4: bindings deleted or added'; end if;
  raise notice 'G4 ok: no binding removed; a refused binding stays as a mismatch row with its reason';
end $f$;
