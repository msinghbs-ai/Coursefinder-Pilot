-- CF-247 D7 (Platform Admin decision pack 3 Nov 2026 21:50 item 7; overnight mandate 21:59 D7): the CRICOS identity guard. A page is never bound
-- to a course by its title alone when the same page is the CRICOS-proved page of another active course of the same provider (that course's code
-- is on the page). Built and shipped switched off; evaluated read-only before activation.
-- Why (live, read-only, 3 Nov 2026 22:16-22:46 AEDT): Swinburne 088407E (Bachelor of ICT (Professional)) is bound by exact title to the page
--   .../bachelor-of-information-and-communication-technology-professional/ while 095881J is bound to the same page (no trailing slash, the same
--   text_sha) because the page states 095881J (identity_basis cricos_code). Both stored copies are one page; the page proves 095881J, not 088407E,
--   and the page fee (44,300) reached 088407E. The scholarship agent counted 214 such addresses and 633 of 1,780 shared-page links whose stored copy
--   was read for another course (method not recorded). This change's own evaluation, read live 3 Nov 2026 22:56 AEDT: 559 title-only bindings
--   (active, not by hand, not locked) on 526 addresses at 185 providers would be refused (556 same address, 3 same page text; 556 exact_title,
--   3 adapter_title; most RMIT 44, Swinburne 39, UTS 31). Shared pages: 4,164 links on 1,829 addresses; 1,282 stored copies read for another course. Today's binding guard (E16, trigger coverage_page_refused_host) checks the page against the course's own title,
--   level and variants; it does not ask whether the page proves a different course.
-- What:
--   1 Settings: binding.cricos_identity_guard_on (0, off), binding.title_identity_bases (the identity bases that are a title, not a code).
--   2 security.cricos_identity_conflict_v1(course, url, text_sha): the other active courses of the provider whose CRICOS-proved binding is the same
--     page (the same address however written, or the same page text).
--   3 Trigger coverage_page_refused_host_zz_cricos (BEFORE INSERT OR UPDATE OF url, status, identity_basis, after the E16 guard): while the switch
--     is on, a binding whose identity is a title only and whose page proves another course is refused the way E16 refuses (status mismatch,
--     read_status cricos_identity_refused, the refusal recorded and routed through security.binding_refusal_route_v1). A page set by hand, a
--     course locked by hand and a course whose own code is on the page are never touched.
--   4 security.cricos_identity_guard_evaluate_v1(provider, sample): read-only report of what the guard would refuse among today's bindings
--     (links, addresses, providers, samples) and of stored copies read for another course. Nothing changes.
-- Replaces: nothing (a new check beside the E16 guard; security.coverage_page_refused_host_guard is not edited)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3). No Firecrawl or AI spend. Off at deploy: activation is a separate recorded
-- settings change after the evaluation (decision pack item 7).

do $g$
begin
  if to_regprocedure('security.layer4_url_key_v1(text)') is null then raise exception 'security.layer4_url_key_v1 (v2.15.438) must exist'; end if;
  if to_regprocedure('security.binding_refusal_route_v1(uuid,text,jsonb,text,uuid)') is null then raise exception 'security.binding_refusal_route_v1 (E16) must exist'; end if;
  -- fixed: the E16 guard this one runs after, as it is live (not edited here)
  if md5(pg_get_functiondef('security.coverage_page_refused_host_guard()'::regprocedure)) <> 'f2e4102f8788816c3f22f26945785f55' then
    raise exception 'live security.coverage_page_refused_host_guard differs from the definition this change was written against (md5 %)',
      md5(pg_get_functiondef('security.coverage_page_refused_host_guard()'::regprocedure));
  end if;
end $g$;

-- 1 settings (G2; Settings > Pipeline settings, section Course pages) -------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'binding.cricos_identity_guard_on', 'Course pages: refuse a title match on a page that proves another course',
  'On (1): a page bound to a course by its title alone is refused when the same page is the CRICOS-proved page of another active course of the same university (that course''s code is on the page); the refusal is recorded and routed like the other binding refusals. Off (0): such bindings stand. Evaluate first with security.cricos_identity_guard_evaluate_v1.',
  'number', to_jsonb(0), 0, 1, 'on (1) or off (0)', 1240, 'Course pages', 'trigger coverage_page_refused_host_zz_cricos (security.cricos_identity_guard_trg_v1)',
  'Platform Admin decision pack 3 Nov 2026 21:50 item 7; overnight mandate 21:59 D7: ships off, evaluated before activation'),
 ('pipeline', 'binding.title_identity_bases', 'Course pages: identity bases that are a title, not a code',
  'A binding whose identity basis is one of these was proved by the course title (or title and level, field and award, degree name) rather than by a code on the page.',
  'list', '["exact_title", "adapter_title", "field_award", "title_level", "degree_name"]'::jsonb, null, null, 'identity bases', 1241, 'Course pages',
  'security.cricos_identity_guard_trg_v1; security.cricos_identity_guard_evaluate_v1', 'Live identity bases 3 Nov 2026 22:26 (code bases: cricos_code, nzqa_code, adapter_code, manual)'),
 ('pipeline', 'binding.cricos_guard_sample', 'Course pages: samples shown by the CRICOS identity evaluation',
  'The evaluation lists at most this many example bindings it would refuse.',
  'number', to_jsonb(50), 0, 1000, 'bindings', 1242, 'Course pages', 'security.cricos_identity_guard_evaluate_v1', 'Decision pack item 7 ("review the affected addresses")')
on conflict do nothing;

-- 2 the conflict ---------------------------------------------------------------------------------------------------------------------------
create or replace function security.cricos_identity_conflict_v1(p_course uuid, p_url text, p_text_sha text default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- The other active courses of the same provider, with a different code, whose binding is proved by their CRICOS code on this same page: the same
-- address however written (security.layer4_url_key_v1), or the same page text (candidates text_sha). {conflict, courses: [{course_id, code, how}]}.
  with me as (select c.id, c.provider_id, c.course_code from catalogue.courses c where c.id = p_course),
       o as (select g.course_id, c2.course_code code,
                    case when security.layer4_url_key_v1(g.url) = security.layer4_url_key_v1(p_url) then 'same address' else 'same page text' end how
               from me join pipeline.coverage_course_pages g on g.provider_id = me.provider_id
               join catalogue.courses c2 on c2.id = g.course_id
              where g.course_id <> me.id and g.identity_basis = 'cricos_code' and g.status in ('bound', 'ambiguous') and c2.lifecycle_status = 'active'
                and c2.course_code is distinct from me.course_code
                and (security.layer4_url_key_v1(g.url) = security.layer4_url_key_v1(p_url)
                     or (nullif(p_text_sha, '') is not null and g.candidates->>'text_sha' = p_text_sha)))
  select jsonb_build_object('conflict', exists (select 1 from o),
                            'courses', coalesce((select jsonb_agg(jsonb_build_object('course_id', o.course_id, 'code', o.code, 'how', o.how) order by o.code) from o), '[]'::jsonb))
$function$;
revoke all on function security.cricos_identity_conflict_v1(uuid, text, text) from public, anon, authenticated;

-- 3 the guard (off at deploy) --------------------------------------------------------------------------------------------------------------------
create or replace function security.cricos_identity_guard_trg_v1() returns trigger
language plpgsql security definer set search_path to '' as $function$
-- Trigger coverage_page_refused_host_zz_cricos (after coverage_page_refused_host, the E16 guard). While binding.cricos_identity_guard_on is 1:
-- a binding (bound or ambiguous) whose identity basis is a title (binding.title_identity_bases), not set by hand and not on a course locked by
-- hand, whose page is the CRICOS-proved page of another active course of the provider, is refused as E16 refuses: the refusal is recorded and
-- routed (security.binding_refusal_route_v1), status mismatch, read_status cricos_identity_refused. Checked only when the binding, its address
-- or its identity basis changes.
declare v_c jsonb; v_codes text;
begin
  if security.pipeline_num_v1('binding.cricos_identity_guard_on', 0) < 1 then return new; end if;
  if new.status not in ('bound', 'ambiguous') or coalesce(new.basis, '') = 'manual'
     or not (coalesce(new.identity_basis, '') = any (security.pipeline_list_v1('binding.title_identity_bases', '[]'::jsonb))) then return new; end if;
  if tg_op = 'UPDATE' and new.url is not distinct from old.url and new.status is not distinct from old.status and new.identity_basis is not distinct from old.identity_basis then
    return new;
  end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = new.course_id and k.field in ('official_url', 'course_url')) then return new; end if;
  v_c := security.cricos_identity_conflict_v1(new.course_id, coalesce(nullif(new.candidates->>'final_url', ''), new.url), new.candidates->>'text_sha');
  if not coalesce((v_c->>'conflict')::boolean, false) then return new; end if;
  select string_agg(x->>'code', ', ') into v_codes from jsonb_array_elements(v_c->'courses') x;
  perform security.binding_refusal_route_v1(new.course_id, new.url,
            jsonb_build_object('verdict', 'refuse', 'rule', 'cricos_identity',
                               'reason', 'the page states the CRICOS code of another course (' || v_codes || '), and this course matched it by title only', 'checks', v_c),
            coalesce(new.basis, 'unknown'), new.evidence_id);
  new.status := 'mismatch'; new.read_status := 'cricos_identity_refused'; new.identity_basis := null; new.next_read_at := null;
  return new;
end $function$;
revoke all on function security.cricos_identity_guard_trg_v1() from public, anon, authenticated;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'coverage_page_refused_host_zz_cricos' and tgrelid = 'pipeline.coverage_course_pages'::regclass) then
    create trigger coverage_page_refused_host_zz_cricos before insert or update of url, status, identity_basis on pipeline.coverage_course_pages
      for each row execute function security.cricos_identity_guard_trg_v1();
  end if;
end $t$;

-- 4 the evaluation (read only) -----------------------------------------------------------------------------------------------------------------
create or replace function security.cricos_identity_guard_evaluate_v1(p_provider uuid default null) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- What the guard would refuse among today's bindings, if it were on and each binding were checked again: title-only bindings (not by hand, not
-- locked by hand) of active courses whose page is the CRICOS-proved page of another active course of the provider (same address or same page
-- text). Also counted: shared pages (one address bound to more than one course) and their stored copies read for another course. Nothing changes.
  with tb as (select x from unnest(security.pipeline_list_v1('binding.title_identity_bases', '[]'::jsonb)) x),
  g as (select g.course_id, g.provider_id, g.url, g.basis, g.identity_basis ib, g.evidence_id, g.candidates->>'text_sha' sha, security.layer4_url_key_v1(g.url) k,
               c.course_code, c.lifecycle_status life
          from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id
         where g.status in ('bound', 'ambiguous') and (p_provider is null or g.provider_id = p_provider)),
  proved as (select provider_id, k, sha, course_id, course_code from g where ib = 'cricos_code' and life = 'active'),
  cand as (select g.* from g where g.life = 'active' and g.ib in (select x from tb) and coalesce(g.basis, '') <> 'manual'
             and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g.course_id and l.field in ('official_url', 'course_url'))),
  -- two equality joins (an address join and a page-text join), not one join on either: the planner can hash each
  pair as (select c.course_id, p.course_code other_code, p.course_id other_course, 'same address' how, 1 o
             from cand c join proved p on p.provider_id = c.provider_id and p.k = c.k
            where p.course_id <> c.course_id and p.course_code is distinct from c.course_code
           union all
           select c.course_id, p.course_code, p.course_id, 'same page text', 2
             from cand c join proved p on p.provider_id = c.provider_id and p.sha = c.sha
            where c.sha is not null and p.course_id <> c.course_id and p.course_code is distinct from c.course_code),
  hit as (select distinct on (c.course_id) c.*, x.other_code, x.other_course, x.how
            from pair x join cand c using (course_id)
           order by c.course_id, x.o, x.other_code),
  shared as (select g.k from g group by g.k having count(distinct g.course_id) > 1),
  sl as (select g.*, (select e.metadata->>'course_id' from pipeline.evidence_artifacts e where e.id = g.evidence_id) ev_course from g join shared using (k))
  select jsonb_build_object(
    'switch_on', security.pipeline_num_v1('binding.cricos_identity_guard_on', 0) >= 1,
    'provider_id', p_provider,
    'would_refuse', jsonb_build_object('bindings', (select count(*) from hit), 'addresses', (select count(distinct k) from hit),
                                      'providers', (select count(distinct provider_id) from hit),
                                      'by_how', (select coalesce(jsonb_object_agg(how, n), '{}'::jsonb) from (select how, count(*) n from hit group by 1) z),
                                      'by_identity_basis', (select coalesce(jsonb_object_agg(ib, n), '{}'::jsonb) from (select ib, count(*) n from hit group by 1) z),
                                      'by_provider', (select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'name', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = z.provider_id), 'bindings', n) order by n desc), '[]'::jsonb)
                                                        from (select provider_id, count(*) n from hit group by 1) z),
                                      'sample', (select coalesce(jsonb_agg(jsonb_build_object('course_id', course_id, 'code', course_code, 'url', url, 'identity_basis', ib,
                                                                                               'page_proves', other_code, 'other_course_id', other_course, 'how', how) order by course_code), '[]'::jsonb)
                                                   from (select * from hit order by course_code limit security.pipeline_num_v1('binding.cricos_guard_sample', 50)::int) s)),
    'shared_pages', jsonb_build_object('links', (select count(*) from sl), 'addresses', (select count(distinct k) from sl),
                                       'copies_read_for_another_course', (select count(*) from sl where ev_course is not null and ev_course <> course_id::text)),
    'note', 'Read only. The guard acts on a binding when it is bound, re-bound or its identity changes; bindings that do not change are not re-checked by it.')
$function$;
revoke all on function security.cricos_identity_guard_evaluate_v1(uuid) from public, anon, authenticated;

-- 5 component register ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.cricos_identity_conflict_v1', 'Layer 2', 'D7: other courses whose CRICOS-proved page is this page', 'active', '{}', '20261104200000'),
 ('function', 'security.cricos_identity_guard_trg_v1', 'Layer 2', 'D7: refuse a title-only binding on a page that proves another course (switch, off)', 'active', '{}', '20261104200000'),
 ('function', 'security.cricos_identity_guard_evaluate_v1', 'Layer 2', 'D7: read-only evaluation of the CRICOS identity guard', 'active', '{}', '20261104200000')
on conflict do nothing;
