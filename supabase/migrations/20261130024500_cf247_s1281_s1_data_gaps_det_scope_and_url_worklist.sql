-- CF-247 s1281 (S1-Data-Gaps; Atlas brief 26 Nov 2026 22:19 AEDT; Platform Admin approvals of S1-DG-2 option B and S1-DG-3 option A, admin PR #1213 follow-up).
-- What, S1-DG-2 ($0 intake sweep over the stored pages outside its provider types):
--   * a dedicated scope setting, fid.provider_types, for the deterministic fee, intake and deadline sweep (fid-det-sweep). It starts with the five types the sweep reads today
--     and adds private_vet, school and wananga, the three types that hold the stored pages the sweep has never been offered (live read 26 Nov 2026 22:2x AEDT:
--     AU private_vet 6,152 pages, NZ private_vet 449, AU school 246, NZ wananga 88);
--   * security.fid_det_batch_v1 reads fid.provider_types in place of fees.provider_types (md5-guarded counted text edit, one edit). Everything else in the function is unchanged.
--   * fees.provider_types is NOT changed. It also scopes the AI fee reader (security.fee_reader_in_scope_v1, security.fee_reader_tick_v1); its recorded reason (Platform Admin
--     26 Oct 2026) keeps private_vet and school out of that reader. Widening it would have queued AI fee reads for 290 providers (308 fee-schedule sources). This change spends US$0.
--   * Intake Rule B, the manual locks, the identity and host gates and the Layer 4 cap (fid.layer4_per_run) are in security.fid_det_record_v1 and the reader, which are not touched.
-- What, S1-DG-3 (held official URLs that fail the identity or host check, unlocked only):
--   * the 23 courses (frozen list, each checked again at apply time: active, still failing with the held address, no manual lock on official_url or course_url, not already on the
--     list, no pending official_course_url item in Layer 4) are added to the Course page needed list through security.course_page_needed_add_v1. Nothing is deleted or rewritten:
--     the held address stays in force, the 123 locked courses are not touched, and a person decides each one (add the page, search again, or record that none exists).
--   * the hourly search rule never takes a course that holds an active official link (security.course_page_needed_search_rule_v1), so no automatic search or replacement follows.
-- G1: no job added, removed or (de)activated. G2: one new setting (list) with its reason and an audit event; no number in code except the frozen list size, marked fixed.
-- G3: no consumer object touched (checked 75/48 before and after). Locks: 7,585 unchanged (checked). Spend: none.
-- Replaces: the provider-type scope source of security.fid_det_batch_v1 (same name; md5-guarded text edit, resulting md5 checked; was fees.provider_types, now fid.provider_types).
-- Retires: nothing. Nothing dropped or deleted. Reversal: reverse the edit (body ec678d37e7ed3578ae4c1d06d8308dc8 back to 23f4c2946d9ee8e0cc6778f67b44e657); the 23 list rows are removable by a person.
set local lock_timeout = '5s';  -- fixed: lock wait for the function, setting and list writes
set local statement_timeout = '120s';  -- fixed: one function body is replaced and 23 list rows are written

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;

create temp table s1281_guard on commit drop as
select (select count(*) from cron.job where active) as cron_before,
       (select count(*) from pipeline.manual_locks) as locks_before,
       (select count(*) from catalogue.course_links) as links_before,
       (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') as official_before,
       (select count(*) from catalogue.course_intakes) as intakes_before,
       (select count(*) from pipeline.course_page_needed) as cpn_before,
       (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'fees.provider_types') as fees_types_before;

-- ---------------------------------------------------------------------------------------------------------------------------------
-- S1-DG-2: the sweep's own provider-type scope
-- ---------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'fid.provider_types', 'Deterministic fee, intake and deadline reader: provider types',
        'Provider types whose stored course pages the deterministic sweep reads (no model, US$0). It is separate from Fee reader: provider types, which scopes the AI fee reader, so widening this list adds no AI cost.',
        'list', '["university", "tafe_polytechnic", "other", "higher_education_institute", "university_college", "private_vet", "school", "wananga"]'::jsonb, null, null, 'types', 999, 'Fees and intakes',
        'fid-det-sweep (security.fid_det_batch_v1)',
        'CF-247 s1281 (Platform Admin approval of S1-DG-2 option B, 26 Nov 2026): the five types read until now plus private_vet, school and wananga; fees.provider_types (AI fee reader) unchanged')
on conflict (toolset_key, key) do nothing;
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'toolsets', 'setting', 'pipeline.fid.provider_types',
       jsonb_build_object('before', null, 'after', s.value, 'reason', s.reason, 'via', 'CF-247 s1281 migration'), null
  from pipeline.platform_toolset_settings s
 where s.toolset_key = 'pipeline' and s.key = 'fid.provider_types'
   and not exists (select 1 from pipeline.admin_control_events e where e.target = 'pipeline.fid.provider_types' and e.action = 'setting');

create or replace function pg_temp.edit_counted(p_sig text, p_before text, p_after text, p_olds text[], p_news text[], p_counts int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> p_counts[i] then raise exception '%: edit % must apply exactly % time(s) (found %)', p_sig, i, p_counts[i], v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_counted('security.fid_det_batch_v1(integer,text)', '23f4c2946d9ee8e0cc6778f67b44e657', 'ec678d37e7ed3578ae4c1d06d8308dc8',
array[$o1$and coalesce(t.code, 'other') in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fees.provider_types')$o1$],
array[$n1$and coalesce(t.code, 'other') in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'fid.provider_types')  -- this sweep's own scope (fid.provider_types); the AI fee reader keeps fees.provider_types$n1$],
array[1]);

-- ---------------------------------------------------------------------------------------------------------------------------------
-- S1-DG-3: the 23 unlocked held addresses that fail the identity or host check go to the Course page needed list (a person decides)
-- ---------------------------------------------------------------------------------------------------------------------------------
do $q$
declare
  v_ids constant uuid[] := array[
    '099f27a7-3d71-4424-b68c-c397292648e6', '0f12bea0-4a3e-406b-afa3-fe71a85d7630', '12d2002c-f9cd-42cb-afb5-8cb7ff4cabc5', '1c1e041d-9721-46ca-a85c-621ba7dd7b85',
    '20a4ca1a-271b-4d18-af27-9aa214169ab9', '283a0dd2-0101-45c0-8a09-b0441f51d783', '3c394c56-0f61-48a6-a938-72d1fb44be6f', '59842620-264b-41c9-81fc-d3249037dd6e',
    '6b5874f1-770f-4000-9614-56a6df194724', '6e65f965-5c9b-4a55-9247-ebb55c9cca89', '7732d15b-aea8-44d0-a520-337f16bf7890', '7d251965-18b4-4295-b59c-ac4ec796f64c',
    '892f92ff-bcd2-4197-8bc1-fb4cfb4140eb', '9b914c56-a2b1-4241-b4cb-d5056002f5fd', 'b4e93ff4-c427-4fc4-a506-7bb4c2ff3749', 'b5d0f4e8-793b-4e34-8909-93b1824837eb',
    'ba8d7def-6f2e-48aa-a314-70603abe8d9c', 'cdc06d73-f08b-40fc-9d30-1700df678e62', 'd25f60bb-bd10-4956-8337-cdefdff8b1ce', 'de86b0d9-bb66-4a7d-8b05-ff1fa2c6d9cd',
    'ff065985-b8ea-4508-907e-d42186886479', 'ff63eb8b-2705-4db7-8500-1db2c548216a', 'ffa5a67a-84e4-4810-9adc-2d8fa6c1d676']::uuid[];
  v_expected constant int := 23;  -- fixed: the size of the list read live and approved (S1-DG-3 option A); a different count changes nothing
  r record; v_n int := 0;
begin
  for r in
    select c.id course_id, lk.url link_url, pg.read_status rs, pg.evidence_id
      from unnest(v_ids) u(id)
      join catalogue.courses c on c.id = u.id and c.lifecycle_status = 'active'
      join lateral (select l.url from catalogue.course_links l
                     where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active'
                     order by l.is_primary desc nulls last, l.updated_at desc nulls last limit 1) lk on true
      join pipeline.coverage_course_pages pg on pg.course_id = c.id
     where pg.read_status in ('identity_mismatch', 'identity_refused', 'refused_host', 'not_course_page')
       and security.layer4_url_key_v1(lk.url) = security.layer4_url_key_v1(pg.url)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and (k.field like 'link:%' or k.field in ('official_url', 'course_url', 'all')))
       and not exists (select 1 from pipeline.course_page_needed n where n.course_id = c.id)
       and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = c.id and i.field_code = 'official_course_url' and i.status = 'pending')
     order by c.id
  loop
    perform security.course_page_needed_add_v1(r.course_id, r.link_url,
      format('The address held for this course was read and refused (%s): the page is not proved to be this course''s own page. The address is kept as it is; a person decides: add the right page, search again, or record that the course has no page of its own (S1-Data-Gaps, Platform Admin approval of S1-DG-3 option A, 26 Nov 2026).', r.rs),
      's1281 url alignment', r.evidence_id, null);
    v_n := v_n + 1;
  end loop;
  if v_n <> v_expected then
    raise exception 'count guard: % of % courses still qualify; nothing was added to the list', v_n, v_expected;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'course_page_needed_add', 'pipeline.course_page_needed',
          jsonb_build_object('courses', v_n, 'lane', 's1281 url alignment', 'via', 'CF-247 s1281 migration', 'locked_courses_untouched', true, 'addresses_deleted', 0), null);
end $q$;

-- ---------------------------------------------------------------------------------------------------------------------------------
-- post-checks (a failure raises and the whole migration rolls back)
-- ---------------------------------------------------------------------------------------------------------------------------------
do $p$
declare v jsonb := security.consumer_api_check_v1(); g s1281_guard%rowtype;
begin
  select * into g from s1281_guard;
  if md5((select prosrc from pg_proc where oid = 'security.fid_det_batch_v1(integer,text)'::regprocedure)) <> 'ec678d37e7ed3578ae4c1d06d8308dc8' then
    raise exception 'post-check: fid_det_batch_v1 is not the edited text';
  end if;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API drifted: %', v;
  end if;
  if (select count(*) from cron.job where active) <> g.cron_before then raise exception 'post-check: active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> g.locks_before then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from catalogue.course_links) <> g.links_before then raise exception 'post-check: course links changed'; end if;
  if (select count(*) from catalogue.course_links where link_type = 'official_course' and status = 'active') <> g.official_before then raise exception 'post-check: official addresses changed'; end if;
  if (select count(*) from catalogue.course_intakes) <> g.intakes_before then raise exception 'post-check: intake rows changed'; end if;
  if (select count(*) from pipeline.course_page_needed) <> g.cpn_before + 23 then raise exception 'post-check: the list did not grow by exactly 23'; end if;  -- fixed: the approved list size
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'fees.provider_types') is distinct from g.fees_types_before then
    raise exception 'post-check: fees.provider_types (the AI fee reader scope) changed';
  end if;
  if (select jsonb_array_length(value) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'fid.provider_types') <> 8 then  -- fixed: five existing types plus three added
    raise exception 'post-check: fid.provider_types is not the eight approved types';
  end if;
  if exists (select 1 from pipeline.course_page_needed n join pipeline.manual_locks k on k.entity = 'course' and k.entity_id = n.course_id and k.field in ('official_url', 'course_url')
              where n.last_refused_lane = 's1281 url alignment') then
    raise exception 'post-check: a course with a manual address lock was added to the list';
  end if;
end $p$;
