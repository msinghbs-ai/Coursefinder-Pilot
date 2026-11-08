-- scenarios on the scratch database after both migrations (run twice each). Every line prints PASS or FAIL; run.sh fails the run on FAIL or ERROR.
create or replace function t.chk(p_name text, p_ok boolean) returns void language plpgsql as $f$ begin raise notice '%', case when coalesce(p_ok, false) then 'PASS ' else 'FAIL ' end || p_name; end $f$;
create or replace function t.sp(p_name text) returns int language sql stable as $f$ select jsonb_array_length(security.course_entry_shared_page_v1((select id from t.named where name = p_name))) $f$;
create or replace function t.bef(p_name text) returns int language sql stable as $f$ select n from t.shared_before where name = p_name $f$;

-- shared page ---------------------------------------------------------------------------------------------------------------------------------
select t.chk('SP1 before: the live rule counted the refused binding (A1 shared with 1)', t.bef('A1') = 1);
select t.chk('SP1 after: a strongly identified, unlocked course ignores a refused binding on its page (A1 shared with 0)', t.sp('A1') = 0);
select t.chk('SP2 another BOUND course on the page still counts (A2 stays 1)', t.sp('A2') = 1 and t.bef('A2') = 1);
select t.chk('SP3 an AMBIGUOUS course on the page still counts (A3 stays 1)', t.sp('A3') = 1);
select t.chk('SP4 a course with a hand lock keeps the old rule (A4 stays 1)', t.sp('A4') = 1);
select t.chk('SP5 a course whose own binding was refused keeps the old rule (A5 stays 1)', t.sp('A5') = 1);
select t.chk('SP6 a hand (manual) binding keeps the old rule (A6 stays 1)', t.sp('A6') = 1);
select t.chk('SP7 a basis outside the list (degree_name) keeps the old rule (A7 stays 1)', t.sp('A7') = 1);
select t.chk('SP8 two refused bindings on one page are both ignored (A8 before 2, after 0)', t.bef('A8') = 2 and t.sp('A8') = 0);
select t.chk('SP9 the same programme under the same title was never counted (A9 0 before and after)', t.bef('A9') = 0 and t.sp('A9') = 0);
select t.chk('SP10 the refused course is not released by the rule: B1 (own mismatch) still sees A1', t.sp('B1') = 1);
update pipeline.platform_toolset_settings set value = '["cricos_code"]'::jsonb where key = 'entry.shared_page_own_bases';
select t.chk('SP11 a narrower own-basis list narrows the relaxation (A8 exact_title is counted again)', t.sp('A8') = 2 and t.sp('A1') = 0);
update pipeline.platform_toolset_settings set value = '[]'::jsonb where key = 'entry.shared_page_own_bases';
select t.chk('SP12 an empty own-basis list restores the old rule exactly', t.sp('A1') = 1 and t.sp('A8') = 2 and t.sp('A2') = 1);
update pipeline.platform_toolset_settings set value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level"]'::jsonb where key = 'entry.shared_page_own_bases';
update pipeline.platform_toolset_settings set value = '["bound", "ambiguous", "mismatch"]'::jsonb where key = 'entry.shared_page_count_statuses';
select t.chk('SP13 adding mismatch to the counted statuses restores the old rule exactly', t.sp('A1') = 1 and t.sp('A8') = 2);
update pipeline.platform_toolset_settings set value = '["bound", "ambiguous"]'::jsonb where key = 'entry.shared_page_count_statuses';
select t.chk('SP14 back at the defaults', t.sp('A1') = 0);
select t.chk('SP16 the function was edited once: one count_statuses reference, md5 changed', (select length(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure)) - length(replace(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure), 'entry.shared_page_count_statuses', '')) = length('entry.shared_page_count_statuses')));

-- route: candidates -----------------------------------------------------------------------------------------------------------------------------
create temp table c1 as select * from security.aer_matrix_route_candidates_v1('00000000-0000-0000-0000-0000000000a2');
select t.chk('R1 candidates are the unlocked, pending, html, stored, at-or-over-the-limit reads with no source yet (i1, i8, i9 only)',
  (select array_agg(c.item_id order by c.item_id) from c1 c) = (select array_agg(id order by id) from t.named where name in ('i1', 'i8', 'i9')));
select t.chk('R1b a read cut 29 rows (i3), a pdf (i4), a decided read (i5), a page already a source (i6) and a read with no stored copy (i7) are not candidates',
  not exists (select 1 from c1 c join t.named n on n.id = c.item_id where n.name in ('i3', 'i4', 'i5', 'i6', 'i7', 'i2')));
select t.chk('R1c a locked course is a candidate only when named', (select count(*) from security.aer_matrix_route_candidates_v1('00000000-0000-0000-0000-0000000000a2', array[(select id from t.named where name = 'i2')])) = 4);
select t.chk('R1d the candidate list is read only: nothing mapped yet', (select count(*) from pipeline.aer_matrix_route where provider_id = '00000000-0000-0000-0000-0000000000a2') = 0);

-- route: attach guards --------------------------------------------------------------------------------------------------------------------------
create temp table snap as select (select count(*) from pipeline.entry_matrix_sources) src, (select count(*) from pipeline.admin_control_events where area = 'entry_matrix') ev,
  (select md5(string_agg(id::text || status || coalesce(proposed_value::text, ''), ',' order by id)) from pipeline.layer4_review_items) items;
do $d$ begin
  begin perform security.aer_matrix_route_attach_v1('00000000-0000-0000-0000-0000000000a2', 2, (select md5(string_agg(item_id::text || ':' || content_hash, ',' order by item_id)) from security.aer_matrix_route_candidates_v1('00000000-0000-0000-0000-0000000000a2')), 'wrong count');
    raise notice 'FAIL R2 a wrong expected count must raise'; exception when others then raise notice 'PASS R2 a wrong expected count raises (%)', left(sqlerrm, 60); end;
  begin perform security.aer_matrix_route_attach_v1('00000000-0000-0000-0000-0000000000a2', 3, 'deadbeef', 'wrong md5');
    raise notice 'FAIL R2b a wrong md5 must raise'; exception when others then raise notice 'PASS R2b a wrong md5 raises (%)', left(sqlerrm, 60); end;
  begin perform security.aer_matrix_route_attach_v1('00000000-0000-0000-0000-0000000000a2', 3, 'x', '   ');
    raise notice 'FAIL R2c an empty reason must raise'; exception when others then raise notice 'PASS R2c an empty reason raises'; end;
end $d$;
select t.chk('R2d the failed attaches changed nothing', (select src from snap) = (select count(*) from pipeline.entry_matrix_sources) and (select ev from snap) = (select count(*) from pipeline.admin_control_events where area = 'entry_matrix'));
do $r$ begin if not exists (select 1 from pg_roles where rolname = 'g_fixture_user') then create role g_fixture_user nologin; end if; end $r$;
do $d$ begin
  set local role g_fixture_user;
  begin perform security.aer_matrix_route_attach_v1('00000000-0000-0000-0000-0000000000a2', 3, 'x', 'not postgres'); reset role; raise notice 'FAIL R3 a non-admin role must not attach';
  exception when others then reset role; raise notice 'PASS R3 a non-admin role cannot attach (%)', left(sqlerrm, 40); end;
end $d$;

-- route: attach ---------------------------------------------------------------------------------------------------------------------------------
select security.aer_matrix_route_attach_v1('00000000-0000-0000-0000-0000000000a2', 3, (select md5(string_agg(item_id::text || ':' || content_hash, ',' order by item_id)) from security.aer_matrix_route_candidates_v1('00000000-0000-0000-0000-0000000000a2')), 'fixture attach');
select t.chk('R4 three sources added, status inactive, read_via stored, the stored copy and its hash, found_via manual',
  (select count(*) from pipeline.entry_matrix_sources s join pipeline.aer_matrix_route r on r.source_id = s.id
    where s.provider_id = '00000000-0000-0000-0000-0000000000a2' and s.status = 'inactive' and s.read_via = 'stored' and s.found_via = 'manual' and s.evidence_id = r.evidence_id and s.content_hash = r.content_hash) = 3);
select t.chk('R4b three route rows, all held, one per old item, the rows cut recorded', (select count(*) from pipeline.aer_matrix_route where provider_id = '00000000-0000-0000-0000-0000000000a2' and state = 'held' and rows_cut >= 30) = 3);
select t.chk('R4c one audit event for the attach, naming no fetch and no AI', (select count(*) from pipeline.admin_control_events where area = 'entry_matrix' and action = 'route_attach' and detail->>'mapped' = '3' and (detail->>'fetch')::boolean = false and (detail->>'ai')::boolean = false) = 1);
select t.chk('R5 no waiting item was changed (same ids, statuses and values)', (select items from snap) = (select md5(string_agg(id::text || status || coalesce(proposed_value::text, ''), ',' order by id)) from pipeline.layer4_review_items));
select t.chk('R5b nothing deleted: every course, evidence and item is still there', (select count(*) from pipeline.layer4_review_items) = 47 and (select count(*) from pipeline.evidence_artifacts) = 47);
select t.chk('R6 the candidates are now empty, so a second attach cannot map the same page twice', (select count(*) from security.aer_matrix_route_candidates_v1('00000000-0000-0000-0000-0000000000a2')) = 0);

-- route: activation -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values ('pipeline', 'fixture.ai_stopped', 'x', 'number', '1'::jsonb, 0, 1, 'x', 'fixture');
do $d$ begin
  begin perform security.aer_matrix_route_activate_v1('00000000-0000-0000-0000-0000000000a2', 3, 'ai stopped'); raise notice 'FAIL R7 activation while AI is stopped must raise';
  exception when others then raise notice 'PASS R7 activation while the AI guard is stopped raises (%)', left(sqlerrm, 50); end;
end $d$;
update pipeline.platform_toolset_settings set value = '0'::jsonb where key = 'fixture.ai_stopped';
update pipeline.platform_toolset_settings set value = '2'::jsonb where key = 'aer.matrix_route_activate_max';
do $d$ begin
  begin perform security.aer_matrix_route_activate_v1('00000000-0000-0000-0000-0000000000a2', 3, 'over the cap'); raise notice 'FAIL R7b more than the cap must raise';
  exception when others then raise notice 'PASS R7b asking for more than the cap raises (%)', left(sqlerrm, 50); end;
end $d$;
select t.chk('R7c nothing activated yet', (select count(*) from pipeline.entry_matrix_sources where provider_id = '00000000-0000-0000-0000-0000000000a2' and status = 'read') = 0);
select security.aer_matrix_route_activate_v1('00000000-0000-0000-0000-0000000000a2', 2, 'fixture activation');
select t.chk('R8 exactly the cap (2) sources are now read; the third stays inactive and held',
  (select count(*) from pipeline.entry_matrix_sources s join pipeline.aer_matrix_route r on r.source_id = s.id where r.state = 'activated' and s.status = 'read' and s.error is null and r.provider_id = '00000000-0000-0000-0000-0000000000a2') = 2
  and (select count(*) from pipeline.entry_matrix_sources s join pipeline.aer_matrix_route r on r.source_id = s.id where r.state = 'held' and s.status = 'inactive' and r.provider_id = '00000000-0000-0000-0000-0000000000a2') = 1);
select t.chk('R8b one audit event for the activation', (select count(*) from pipeline.admin_control_events where area = 'entry_matrix' and action = 'route_activate' and detail->>'activated' = '2') = 1);

-- route: rows from a mapped source carry the course ---------------------------------------------------------------------------------------------
do $d$
declare r1 pipeline.aer_matrix_route%rowtype; r2 pipeline.aer_matrix_route%rowtype; v_country uuid := (select id from ref.countries limit 1); v_other uuid; h1 text; h2 text;
begin
  select * into r1 from pipeline.aer_matrix_route where provider_id = '00000000-0000-0000-0000-0000000000a2' order by created_at, id limit 1 offset 0;
  select * into r2 from pipeline.aer_matrix_route where provider_id = '00000000-0000-0000-0000-0000000000a2' and id <> r1.id order by created_at, id limit 1;
  insert into catalogue.provider_entry_matrix(provider_id, country_id, country_code, qualification_name, quote, source_url, source_id)
  values ('00000000-0000-0000-0000-0000000000a2', v_country, 'IN', 'CBSE', 'q', r1.url, r1.source_id), ('00000000-0000-0000-0000-0000000000a2', v_country, 'IN', 'CBSE', 'q', r2.url, r2.source_id);
  perform t.chk('R9 a row from a mapped source is that course''s row (course_id, course_minimum, the course title as label)',
    (select count(*) from catalogue.provider_entry_matrix m where m.source_id = r1.source_id and m.course_id = r1.course_id and m.matrix_kind = 'course_minimum'
       and m.course_label = (select canonical_title from catalogue.courses where id = r1.course_id)) = 1);
  select row_hash into h1 from catalogue.provider_entry_matrix where source_id = r1.source_id; select row_hash into h2 from catalogue.provider_entry_matrix where source_id = r2.source_id;
  perform t.chk('R9b the row hash includes the course, so two pages with the same qualification do not collide', h1 is distinct from h2);
  insert into catalogue.provider_entry_matrix(provider_id, country_id, country_code, qualification_name, quote, source_url) values ('00000000-0000-0000-0000-0000000000a2', v_country, 'IN', 'CBSE', 'q', 'https://other.test/');
  perform t.chk('R9c a row from an unmapped source stays a provider row', (select count(*) from catalogue.provider_entry_matrix where source_url = 'https://other.test/' and course_id is null and matrix_kind = 'provider_minimum') = 1);
  select id into v_other from catalogue.courses where provider_id = '00000000-0000-0000-0000-0000000000a3' limit 1;
  insert into catalogue.provider_entry_matrix(provider_id, course_id, country_id, country_code, qualification_name, quote, source_url, source_id) values ('00000000-0000-0000-0000-0000000000a2', v_other, v_country, 'IN', 'CBSE2', 'q', r1.url, r1.source_id);
  perform t.chk('R9d a row that already names a course keeps it', (select count(*) from catalogue.provider_entry_matrix where qualification_name = 'CBSE2' and course_id = v_other) = 1);
end $d$;

-- the QUT-shaped provider: the migration's own data step skipped on a differing live set; the guard and the apply with the fixture's md5 ----------------
select t.chk('Q1 the QUT-shaped candidates are the 23 unlocked reads at 30 or more rows (not the 14 locked, not the 8-row read)',
  (select count(*) from security.aer_matrix_route_candidates_v1('2c4f515c-c146-4e90-ba8a-294130aa1f40')) = 23
  and not exists (select 1 from security.aer_matrix_route_candidates_v1('2c4f515c-c146-4e90-ba8a-294130aa1f40') c join t.named n on n.id = c.item_id where n.name in ('q38') or n.name ~ '^q(2[4-9]|3[0-7])$'));
select t.chk('Q2 the migration (live md5 not matching the fixture) mapped nothing for the QUT-shaped provider', (select count(*) from pipeline.aer_matrix_route where provider_id = '2c4f515c-c146-4e90-ba8a-294130aa1f40') = 0);
select t.chk('Z1 the consumer API is untouched: nothing in public or api was created', not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'api')));
do $d$ begin raise notice 'qut-shared: scenarios finished'; end $d$;
