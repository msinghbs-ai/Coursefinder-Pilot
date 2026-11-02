-- IQ-00043 link reactivation guard: the cases, on the migrated definitions. Each block raises on a wrong result and prints "ok <case>".
\set ON_ERROR_STOP 1
-- the common admission write as background readers call it (no person: cf.manual_edit off, nobody signed in)
create function pg_temp.adm(p_course text, p_url text) returns jsonb language sql as $$
  select security.coverage_apply_course_v1(p_course::uuid, '00000000-0000-0000-0000-00000000005a', '00000000-0000-0000-0000-0000000000ee', p_url, 'h',
                                           jsonb_build_object('course_url', p_url)) $$;
create function pg_temp.st(p_course text, p_url text) returns text language sql as $$
  select coalesce((select status from catalogue.course_links where course_id = p_course::uuid and link_type = 'official_course' and url = p_url), 'none') $$;
create function pg_temp.shown(p_course text) returns text language sql as $$
  select official_course_url from search.course_documents where course_id = p_course::uuid $$;

-- 1 superseded (the 13): the exit-awards write of the fragment spelling leaves the tranche's inactive link as it was; evidence recorded once
do $c$ declare r jsonb; v_upd timestamptz; begin
  select updated_at into v_upd from catalogue.course_links where id = '10000000-0000-0000-0000-000000000002';
  r := pg_temp.adm('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int');
  if pg_temp.st('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int') <> 'inactive' then raise exception 'case 1: re-activated'; end if;
  if (select updated_at from catalogue.course_links where id = '10000000-0000-0000-0000-000000000002') <> v_upd then raise exception 'case 1: the held row was rewritten'; end if;
  if (r->>'links_applied')::int <> 0 or (r->>'link_held')::boolean is not true then raise exception 'case 1 return: %', r; end if;
  if not exists (select 1 from pipeline.course_link_rediscoveries where link_id = '10000000-0000-0000-0000-000000000002' and route = 'superseded' and seen_count = 1 and attempted = 'insert') then
    raise exception 'case 1: no rediscovery row'; end if;
  perform pg_temp.adm('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int');
  if (select seen_count from pipeline.course_link_rediscoveries where link_id = '10000000-0000-0000-0000-000000000002') <> 2 then raise exception 'case 1: not counted again'; end if;
  if (select count(*) from pipeline.fx_queue_calls where p->>'fingerprint' = 'course-link:reactivation-held') <> 1 then raise exception 'case 1: queue issue not once'; end if;
  -- the same through a direct update (any other writer)
  update catalogue.course_links set status = 'active' where id = '10000000-0000-0000-0000-000000000002';
  if pg_temp.st('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int') <> 'inactive' then raise exception 'case 1: update re-activated'; end if;
  raise notice 'ok 1 superseded: the tranche''s fragment link stays inactive (upsert and update), recorded once with a count, one queue issue';
end $c$;

-- 2 a new spelling of a page set aside is not admitted; the kept page re-read goes on (an active link is never held)
do $c$ declare r jsonb; begin
  r := pg_temp.adm('00000000-0000-0000-0000-000000000002', 'HTTP://uni.example/2020/program/old/#top');
  if pg_temp.st('00000000-0000-0000-0000-000000000002', 'HTTP://uni.example/2020/program/old/#top') <> 'none' then raise exception 'case 2: new spelling admitted'; end if;
  if not exists (select 1 from pipeline.course_link_rediscoveries where course_id = '00000000-0000-0000-0000-000000000002' and route = 'superseded' and basis->>'same_page_as' = 'https://uni.example/2020/program/old') then
    raise exception 'case 2: evidence'; end if;
  r := pg_temp.adm('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it');
  if (r->>'links_applied')::int <> 1 or pg_temp.st('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it') <> 'active' then raise exception 'case 2: kept page re-read %', r; end if;
  raise notice 'ok 2 superseded spelling (scheme, case, slash, fragment) held; the kept page re-read is applied';
end $c$;

-- 3 held: an open remediation hold keeps its link unverified; a pending Layer 4 review keeps an unverified link for the reviewer
do $c$ begin
  perform pg_temp.adm('00000000-0000-0000-0000-000000000003', 'https://uni.example/held');
  if pg_temp.st('00000000-0000-0000-0000-000000000003', 'https://uni.example/held') <> 'unverified' then raise exception 'case 3: hold re-activated'; end if;
  perform pg_temp.adm('00000000-0000-0000-0000-000000000004', 'https://uni.example/c4');
  if pg_temp.st('00000000-0000-0000-0000-000000000004', 'https://uni.example/c4') <> 'unverified' then raise exception 'case 3: pending review pre-empted'; end if;
  if (select count(*) from pipeline.course_link_rediscoveries where route = 'held' and course_id in ('00000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000004')) <> 2 then
    raise exception 'case 3: evidence'; end if;
  raise notice 'ok 3 held: remediation hold and pending Layer 4 review both keep the link as it was';
end $c$;

-- 3b an unverified link with no decision (a dead page that came back) is re-admitted as before
do $c$ begin
  perform pg_temp.adm('00000000-0000-0000-0000-000000000005', 'https://uni.example/c5');
  if pg_temp.st('00000000-0000-0000-0000-000000000005', 'https://uni.example/c5') <> 'active' then raise exception 'case 3b: a recovered page was held'; end if;
  raise notice 'ok 3b an unverified link with no decision is re-admitted';
end $c$;

-- 4 rejected: a Layer 4 "keep the page we hold" decision; then a later approval of the same page lets it in
do $c$ begin
  perform pg_temp.adm('00000000-0000-0000-0000-000000000006', 'https://uni.example/c6-proposed/');
  if pg_temp.st('00000000-0000-0000-0000-000000000006', 'https://uni.example/c6-proposed/') <> 'none' then raise exception 'case 4: rejected page admitted'; end if;
  if pg_temp.shown('00000000-0000-0000-0000-000000000006') <> 'https://uni.example/c6-kept' then raise exception 'case 4: shown'; end if;
  insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, status, proposed_value, decided_at)
    values ('course', '00000000-0000-0000-0000-000000000006', 'official_course_url', 'approved', '{"course_url":"https://uni.example/c6-proposed"}', now());
  perform pg_temp.adm('00000000-0000-0000-0000-000000000006', 'https://uni.example/c6-proposed/');
  if pg_temp.st('00000000-0000-0000-0000-000000000006', 'https://uni.example/c6-proposed/') <> 'active' then raise exception 'case 4: later approval not honoured'; end if;
  raise notice 'ok 4 rejected by Layer 4: held; admitted once a later decision approves the same page';
end $c$;

-- 4b a page rejection holds its page; the query names the page, so the rejected bare listing does not hold a programme page
do $c$ begin
  perform pg_temp.adm('00000000-0000-0000-0000-000000000007', 'https://uni.example/c7-wrong-variant#x');
  if pg_temp.st('00000000-0000-0000-0000-000000000007', 'https://uni.example/c7-wrong-variant#x') <> 'none' then raise exception 'case 4b: rejected page admitted'; end if;
  perform pg_temp.adm('00000000-0000-0000-0000-000000000007', 'https://study.auckland.ac.nz/ords/r/uoa/catalogue/program?p5_code=MC');
  if pg_temp.st('00000000-0000-0000-0000-000000000007', 'https://study.auckland.ac.nz/ords/r/uoa/catalogue/program?p5_code=MC') <> 'active' then raise exception 'case 4b: a programme page was held by the listing rejection'; end if;
  if security.course_link_norm_v1('https://www.latrobe.edu.au/courses/x#/overview?studentType=int') <> security.course_link_norm_v1('HTTPS://latrobe.edu.au/courses/x/') then raise exception 'case 4b: La Trobe spelling'; end if;
  if security.course_link_norm_v1('https://study.auckland.ac.nz/ords/r/uoa/catalogue/program?p5_code=MC') = security.course_link_norm_v1('https://study.auckland.ac.nz/ords/r/uoa/catalogue/program') then raise exception 'case 4b: query dropped'; end if;
  raise notice 'ok 4b page rejection held; Auckland programme page (query) not confused with the rejected listing; La Trobe spelling equal';
end $c$;

-- 5 locked: the existing manual_lock_guard skips the background write first (no change, no rediscovery row needed)
do $c$ declare r jsonb; begin
  r := pg_temp.adm('00000000-0000-0000-0000-000000000008', 'https://uni.example/c8-old');
  if pg_temp.st('00000000-0000-0000-0000-000000000008', 'https://uni.example/c8-old') <> 'inactive' then raise exception 'case 5: locked course changed'; end if;
  if (r->>'link_held')::boolean is not true then raise exception 'case 5 return: %', r; end if;
  if exists (select 1 from pipeline.course_link_rediscoveries where course_id = '00000000-0000-0000-0000-000000000008') then raise exception 'case 5: the lock guard did not run first'; end if;
  raise notice 'ok 5 locked: skipped by manual_lock_guard before the reactivation guard; reported as not applied';
end $c$;

-- 6 retired: a deprecated link and a link from a retired source are not made active
do $c$ begin
  perform pg_temp.adm('00000000-0000-0000-0000-000000000009', 'https://uni.example/c9-retired');
  if pg_temp.st('00000000-0000-0000-0000-000000000009', 'https://uni.example/c9-retired') <> 'deprecated' then raise exception 'case 6: deprecated re-activated'; end if;
  insert into catalogue.course_links(course_id, link_type, url, status, source_id)
    values ('00000000-0000-0000-0000-000000000009', 'official_course', 'https://uni.example/c9-from-retired-source', 'active', '00000000-0000-0000-0000-00000000005c');
  if pg_temp.st('00000000-0000-0000-0000-000000000009', 'https://uni.example/c9-from-retired-source') <> 'none' then raise exception 'case 6: retired source admitted'; end if;
  if (select count(*) from pipeline.course_link_rediscoveries where course_id = '00000000-0000-0000-0000-000000000009' and route = 'retired') <> 2 then raise exception 'case 6: evidence'; end if;
  raise notice 'ok 6 retired: deprecated link and retired source held';
end $c$;

-- 7 a genuinely new link is admitted as before
do $c$ declare r jsonb; begin
  r := pg_temp.adm('00000000-0000-0000-0000-000000000010', 'https://uni.example/c10-new');
  if pg_temp.st('00000000-0000-0000-0000-000000000010', 'https://uni.example/c10-new') <> 'active' or (r->>'links_applied')::int <> 1 or (r->>'link_held')::boolean then raise exception 'case 7: %', r; end if;
  if exists (select 1 from pipeline.course_link_rediscoveries where course_id = '00000000-0000-0000-0000-000000000010') then raise exception 'case 7: evidence for a new link'; end if;
  raise notice 'ok 7 a new course page is admitted (links_applied 1)';
end $c$;

-- 8 a person decides: the course record or a paste file (cf.manual_edit) and a signed-in Layer 4 reviewer re-activate
do $c$ begin
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.course_links set status = 'active' where id = '20000000-0000-0000-0000-000000000002';
  if pg_temp.st('00000000-0000-0000-0000-000000000002', 'https://uni.example/2020/program/old') <> 'active' then raise exception 'case 8: manual edit held'; end if;
  perform set_config('cf.manual_edit', '', true);
  perform set_config('fx.uid', '00000000-0000-0000-0000-00000000aaaa', true);
  update catalogue.course_links set status = 'active' where id = '90000000-0000-0000-0000-000000000001';
  if pg_temp.st('00000000-0000-0000-0000-000000000009', 'https://uni.example/c9-retired') <> 'active' then raise exception 'case 8: reviewer held'; end if;
  perform set_config('fx.uid', '', true);
  raise notice 'ok 8 a person (cf.manual_edit, or signed in) re-activates';
end $c$;

-- 9 the Decision 263 "take" rule never takes a held page (the row waits for a person); a page not held is still taken (E15 apply)
do $c$ declare r jsonb; begin
  insert into catalogue.course_links(id, course_id, link_type, url, is_primary, status, source_id) values
    ('a0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', 'official_course', 'https://uni.example/c11-kept', true, 'active', '00000000-0000-0000-0000-00000000005b'),
    ('a0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000011', 'official_course', 'https://uni.example/c11-replaced', false, 'inactive', '00000000-0000-0000-0000-00000000005a');
  insert into pipeline.fx_plan values
    ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-0000000000bb', null, null, '00000000-0000-0000-0000-0000000000ee', 'h', 'https://uni.example/c11-replaced',
     'official_url', 'differs', '["https://uni.example/c11-kept"]', '{"course_url":"https://uni.example/c11-replaced"}'),
    ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-0000000000bb', null, null, '00000000-0000-0000-0000-0000000000ee', 'h', 'https://uni.example/c12-page',
     'official_url', 'differs', '[null]', '{"course_url":"https://uni.example/c12-page"}');
  r := security.coverage_admission_apply_v1(10, 'fx', array['official_url']);
  if (r->>'layer4')::int <> 1 or (r->>'decided_by_rule')::int <> 1 then raise exception 'case 9: %', r; end if;
  if (select status from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000011') <> 'pending' then raise exception 'case 9: rule took a held page'; end if;
  if pg_temp.st('00000000-0000-0000-0000-000000000011', 'https://uni.example/c11-kept') <> 'active' or pg_temp.st('00000000-0000-0000-0000-000000000011', 'https://uni.example/c11-replaced') <> 'inactive' then
    raise exception 'case 9: links changed'; end if;
  if (select status from pipeline.layer4_review_items where entity_id = '00000000-0000-0000-0000-000000000012') <> 'approved' or pg_temp.st('00000000-0000-0000-0000-000000000012', 'https://uni.example/c12-page') <> 'active' then
    raise exception 'case 9: a page not held was not taken'; end if;
  delete from pipeline.fx_plan;
  raise notice 'ok 9 rule: a replaced page waits for a person (pending); a page not held is taken and applied';
end $c$;

-- 10 the switch (G2): 0 is the old behaviour; the listing then finds the tranche link re-activated by a background source; 1 again
do $c$ declare n int; begin
  update pipeline.platform_toolset_settings set value = '0' where key = 'course_link.reactivation_guard';
  perform pg_temp.adm('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int');
  if pg_temp.st('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int') <> 'active' then raise exception 'case 10: switch off'; end if;
  select count(*) into n from security.course_link_reactivated_v1() where link_id = '10000000-0000-0000-0000-000000000002' and route = 'superseded' and source_type = 'provider_course_page_sweep';
  if n <> 1 then raise exception 'case 10: listing %', n; end if;
  -- the listing leaves person-set links and links not set aside
  if exists (select 1 from security.course_link_reactivated_v1() where link_id <> '10000000-0000-0000-0000-000000000002') then raise exception 'case 10: listing too wide'; end if;
  update pipeline.platform_toolset_settings set value = '1' where key = 'course_link.reactivation_guard';
  raise notice 'ok 10 switch 0 restores the old behaviour; the listing finds exactly the re-activated tranche link';
end $c$;

-- 11 the restore of a measured set: a recorded human decision sets it inactive again; the shown link does not change
do $c$ declare v_before text := pg_temp.shown('00000000-0000-0000-0000-000000000001'); begin
  perform set_config('cf.manual_edit', 'on', true);
  update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now() where id = '10000000-0000-0000-0000-000000000002' and status = 'active' and not is_primary;
  perform set_config('cf.manual_edit', '', true);
  perform search.refresh_course_enrichment_scoped_v1(array['00000000-0000-0000-0000-000000000001'::uuid], true);
  if pg_temp.shown('00000000-0000-0000-0000-000000000001') is distinct from v_before then raise exception 'case 11: shown link changed'; end if;
  if exists (select 1 from security.course_link_reactivated_v1()) then raise exception 'case 11: listing not empty'; end if;
  perform pg_temp.adm('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int');
  if pg_temp.st('00000000-0000-0000-0000-000000000001', 'https://www.latrobe.edu.au/courses/bachelor-of-it#/overview?studentType=int') <> 'inactive' then raise exception 'case 11: re-activated after restore'; end if;
  raise notice 'ok 11 restored set stays restored at the next admission; shown link unchanged; listing empty';
end $c$;
