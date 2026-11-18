-- CF-247 StudySearch SS-007 (ref TD1): the binding remediation hold, and the governed, reversible re-role function.
-- Authority: Platform Admin 31 Oct 2026 11:53 (SS-007 Option 2 with controls) and 12:38 (Executive Execution Mandate §2: Option C, build the
-- hold, tests, dry runs and change control; "Do not execute the production re-role operation that would null 292 consumer-visible URLs until
-- the Platform Admin explicitly approves that data change"). Evidence: admin docs/platform/nz-enrichment-brief/2026-10-31-studysearch-
-- transformation.md §12, §17, §17.1 and §18.
-- Why: re-roling a shared fee, enrolment or course-list page (binding status bound -> mismatch) would otherwise put the course straight back
-- into automated paid and AI lanes. The approval excludes that. This change adds one hold, enforced centrally through controls that already
-- exist, so a held course is not re-searched, re-bound, read or AI-matched until a person lifts the hold:
--   * one indexed table (pipeline.course_remediation_holds; one open hold per course) and one check (security.course_held_v1);
--   * the existing binding guard trigger (coverage_page_refused_host on pipeline.coverage_course_pages) keeps a held course's binding as it
--     is: no lane can bind it again (search pass, course link search, site-map binder, Firecrawl find, re-identification). The page reader
--     reads only bound or ambiguous pages, so it never reads a held course;
--   * the existing one stop gate (security.search_stop_gate_v1), used by every worker-sent course search, returns 'remediation_hold';
--   * AI match preparation skips a held course beside the existing no-page hold;
--   * the course link search tick's direct send path (off today: send_via = worker) skips a held course too.
-- The consumer's official link is catalogue.course_links (projected into search.course_documents.official_course_url), so the re-role also
-- sets the matching active official link to the existing status 'unverified' (as security.link_refresh_tick_v1 does) and requests a search
-- refresh; job course-url-fill (guard 3) takes back courses.course_url as it already does when a binding stops being bound.
-- No job, schedule, time-out or consumer object changes. With no holds open (as shipped) every lane behaves exactly as before.
-- The re-role itself (security.binding_remediation_apply_v1) is run per provider by the Platform Admin's approval only; it is not run here.
-- Replaces: security.coverage_page_refused_host_guard, security.search_stop_gate_v1, security.coverage_ai_match_prepare_v1, security.course_link_search_tick_v1 (same names; md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed by this migration. No new job or status value on any existing table.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 1. The hold, its audit and its rollback record (one row per remediated binding)
create table if not exists pipeline.course_remediation_holds (
  id bigint generated always as identity primary key,
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid not null,
  url text not null,
  action text not null check (action in ('re_role')),
  class text not null,
  reason text not null,
  approval text not null,
  batch_id uuid not null,
  before jsonb not null,
  after jsonb,
  admitted_attributes text[] not null default '{}',
  held_at timestamptz not null default now(),
  held_by text not null default current_user,
  lifted_at timestamptz,
  lifted_by text,
  lift_mode text check (lift_mode in ('restore', 'release')),
  lift_reason text
);
create unique index if not exists course_remediation_holds_open on pipeline.course_remediation_holds (course_id) where lifted_at is null;
create index if not exists course_remediation_holds_provider on pipeline.course_remediation_holds (provider_id, held_at desc);
comment on table pipeline.course_remediation_holds is 'CF-247 StudySearch SS-007 (Platform Admin 31 Oct 2026): binding remediation hold and audit. One row per binding re-roled by security.binding_remediation_apply_v1, with its full before state (page binding, course URL, URL fill, official links), the admitted attributes that depended on the course, and how and why the hold was lifted. While a row is open (lifted_at null) the course is held out of every automated search, binding, page-read and AI-match lane (security.course_held_v1). Rollback: security.binding_remediation_lift_v1. Never read by the consumer API.';
alter table pipeline.course_remediation_holds enable row level security;
revoke all on pipeline.course_remediation_holds from public, anon, authenticated;

create or replace function security.course_held_v1(p_course uuid) returns boolean
language sql stable security definer set search_path to '' as $function$
  -- SS-007: an open binding remediation hold (unique partial index course_remediation_holds_open)
  select exists (select 1 from pipeline.course_remediation_holds h where h.course_id = p_course and h.lifted_at is null)
$function$;
revoke all on function security.course_held_v1(uuid) from public, anon, authenticated;

-- 2. The existing binding guard keeps a held course's binding unchanged (no lane can bind it again); a person's manual lock still wins
select pg_temp.edit_once('security.coverage_page_refused_host_guard()', 'efd59e2a453ab113c4ac49e0413bcce3', '33351b506da59359656ee196218d7882', array[
 array[$o$begin
  if new.status in ('bound', 'ambiguous') and security.refused_host(new.url)$o$, $n$begin
  -- 31 Oct 2026 (StudySearch SS-007): a course under a binding remediation hold keeps its binding until a person lifts the hold
  if tg_op = 'UPDATE' and new.status in ('bound', 'ambiguous') and security.course_held_v1(new.course_id)
     and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = new.course_id and k.field = 'official_url') then
    return old;
  end if;
  if new.status in ('bound', 'ambiguous') and security.refused_host(new.url)$n$]], array[1]);

-- 3. The existing one stop gate (every worker-sent course search) refuses a held course
select pg_temp.edit_once('security.search_stop_gate_v1(uuid,uuid,boolean,boolean)', '6e08df75e43bc95a3f15c5f2763c182d', 'd7679a059ed611cdc4553b70459f549f', array[
 array[$o$  -- SP-1: recorded as no page published by the provider$o$, $n$  -- SS-007 (31 Oct 2026): held for binding remediation until a person lifts the hold
  if p_course is not null and security.course_held_v1(p_course) then
    return 'remediation_hold';
  end if;
  -- SP-1: recorded as no page published by the provider$n$]], array[1]);

-- 4. AI match preparation skips a held course, beside the no-page hold (both places it is checked)
select pg_temp.edit_once('security.coverage_ai_match_prepare_v1(integer,integer)', 'ab2dd5dc2e897b20c9de8bbc84bd26eb', '23d433d2d730fc8d58ffb555a686ca44', array[
 array[$o$and not security.no_page_hold_v1(co.id)  -- SP-1$o$, $n$and not security.no_page_hold_v1(co.id) and not security.course_held_v1(co.id)  -- SS-007: remediation hold; SP-1$n$]], array[2]);

-- 5. The course link search tick's direct send path (off while send_via = worker) skips a held course
select pg_temp.edit_once('security.course_link_search_tick_v1(integer)', '13b0771da8ae1831ff1291bfac82faa6', 'ffc9fb647925f689678a035cdd64b3e1', array[
 array[$o$where s.state = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)$o$, $n$where s.state = 'queued' and not security.course_held_v1(s.course_id) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)$n$]], array[1]);

-- 6. The batch size limit (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'remediation.max_batch_courses', 'Binding remediation: most courses in one batch',
  'The binding remediation function (SS-007) changes at most this many course bindings in one run. Each run is for one provider and must name exactly how many bindings it expects to change.', 'number',
  to_jsonb(50), 1, 200, 'courses', 794, 'Platform upkeep', 'security.binding_remediation_apply_v1',
  'CF-247 StudySearch SS-007 (Platform Admin 31 Oct 2026 11:53): bounded, count-guarded batches')
on conflict do nothing;

-- 7. The governed re-role: one provider, a named list, an exact expected count; every check re-done live; nothing deleted
create or replace function security.binding_remediation_apply_v1(p_provider uuid, p_items jsonb, p_expected int, p_approval text, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_batch uuid := gen_random_uuid(); v_max int := security.pipeline_num_v1('remediation.max_batch_courses', 50)::int;
        v_it jsonb; v_course uuid; v_url text; v_class text; v_pg pipeline.coverage_course_pages%rowtype; v_why text;
        v_ok jsonb := '[]'::jsonb; v_held jsonb := '[]'::jsonb; v_id bigint; n int := 0; v_links int := 0; v_l int;
begin
  if current_user <> 'postgres' then raise exception 'binding remediation is run by the Platform Admin only'; end if;
  if coalesce(btrim(p_approval), '') = '' or coalesce(btrim(p_reason), '') = '' then raise exception 'an approval reference and a reason are required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'p_items must be a non-empty array of {course_id, url, class, also_links}'; end if;
  if jsonb_array_length(p_items) > v_max then raise exception 'batch of % is over the limit of % (setting remediation.max_batch_courses)', jsonb_array_length(p_items), v_max; end if;

  -- every binding is checked again, live; anything that is not exactly as reviewed is held for a person, not changed
  for v_it in select * from jsonb_array_elements(p_items) loop
    v_course := (v_it->>'course_id')::uuid; v_url := v_it->>'url'; v_class := coalesce(v_it->>'class', 'unspecified'); v_why := null;
    select * into v_pg from pipeline.coverage_course_pages where course_id = v_course;
    if v_pg.course_id is null then v_why := 'no binding';
    elsif v_pg.provider_id <> p_provider then v_why := 'another provider';
    elsif v_pg.url is distinct from v_url then v_why := 'the bound page changed since review';
    elsif v_pg.status <> 'bound' then v_why := 'not bound (' || v_pg.status || ')';
    elsif coalesce(v_pg.basis, '') = 'manual' then v_why := 'manual binding';
    elsif exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = v_course and k.field in ('official_url', 'course_url')) then v_why := 'locked by hand';
    elsif not exists (select 1 from catalogue.courses c where c.id = v_course and c.lifecycle_status = 'active') then v_why := 'course not active';
    elsif security.course_held_v1(v_course) then v_why := 'already held';
    end if;
    if v_why is not null then v_held := v_held || jsonb_build_object('course_id', v_course, 'url', v_url, 'why', v_why);
    else v_ok := v_ok || jsonb_build_object('course_id', v_course, 'url', v_url, 'class', v_class, 'also_links', coalesce(v_it->'also_links', '[]'::jsonb)); end if;
  end loop;
  if jsonb_array_length(v_ok) <> p_expected then
    raise exception 'count guard: % bindings pass the checks, % expected; nothing changed. Held: %', jsonb_array_length(v_ok), p_expected, v_held;
  end if;

  for v_it in select * from jsonb_array_elements(v_ok) loop
    v_course := (v_it->>'course_id')::uuid; v_url := v_it->>'url';
    select * into v_pg from pipeline.coverage_course_pages where course_id = v_course for update;
    insert into pipeline.course_remediation_holds(course_id, provider_id, url, action, class, reason, approval, batch_id, before, admitted_attributes)
    values (v_course, p_provider, v_url, 're_role', v_it->>'class', p_reason, p_approval, v_batch,
            jsonb_build_object(
              'page', to_jsonb(v_pg),
              'course_url', (select c.course_url from catalogue.courses c where c.id = v_course),
              'fill', (select to_jsonb(f) from pipeline.course_url_fills f where f.course_id = v_course),
              'official_links', (select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb) from catalogue.course_links l where l.course_id = v_course and l.link_type = 'official_course'),
              'rejected_before', security.page_refused_v1(v_course, v_url)),
            array(select a.attribute from pipeline.course_attribute_coverage a where a.course_id = v_course and a.state = 'admitted' order by 1))
    returning id into v_id;
    -- the page is never bound to this course again (kept; rollback removes only this row)
    insert into pipeline.page_rejections(course_id, url, provider_id, evidence_id, source, reason, signals)
    values (v_course, v_url, p_provider, v_pg.evidence_id, 'binding_remediation', p_reason,
            jsonb_build_object('hold_id', v_id, 'class', v_it->>'class', 'approval', p_approval))
    on conflict (course_id, url) do nothing;
    -- the binding stops being the course page; url, evidence, read result and identity are kept as provenance
    update pipeline.coverage_course_pages set status = 'mismatch', next_read_at = null, leased_until = null
     where course_id = v_course and url = v_url and status = 'bound';
    -- the consumer's official link (catalogue.course_links, projected to search) is set to the existing status 'unverified', as
    -- security.link_refresh_tick_v1 does for a page that is not the course's; courses.course_url is taken back by job course-url-fill (guard 3)
    update catalogue.course_links l set status = 'unverified', is_primary = false, updated_at = now()
     where l.course_id = v_course and l.link_type = 'official_course' and l.status = 'active'
       and (l.url = v_url or l.url in (select jsonb_array_elements_text(v_it->'also_links')));  -- reviewed spellings of the same page (e.g. another host name)
    get diagnostics v_l = row_count; v_links := v_links + v_l;
    update pipeline.course_remediation_holds h set after = jsonb_build_object('page', (select to_jsonb(p) from pipeline.coverage_course_pages p where p.course_id = v_course), 'links_unverified', v_l) where h.id = v_id;
    n := n + 1;
  end loop;
  if n <> p_expected then raise exception 'count guard after change: % changed, % expected', n, p_expected; end if;
  if v_links > 0 then
    insert into search.refresh_requests(requested_by) values ('binding remediation SS-007 batch ' || v_batch || ': ' || v_links || ' official links set unverified');
  end if;
  return jsonb_build_object('batch_id', v_batch, 'provider_id', p_provider, 're_roled', n, 'links_unverified', v_links, 'held_for_person_review', v_held,
                            'note', 'search documents follow at the next search refresh; courses.course_url is taken back by job course-url-fill (guard 3)');
end $function$;
revoke all on function security.binding_remediation_apply_v1(uuid, jsonb, int, text, text) from public, anon, authenticated, service_role;

-- 8. Rollback (restore) or hand back to the normal lanes (release); a person's decision, recorded
create or replace function security.binding_remediation_lift_v1(p_course uuid, p_mode text, p_reason text)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_h pipeline.course_remediation_holds%rowtype; v_p jsonb;
begin
  if current_user <> 'postgres' then raise exception 'a binding remediation hold is lifted by the Platform Admin only'; end if;
  if p_mode not in ('restore', 'release') or coalesce(btrim(p_reason), '') = '' then raise exception 'mode restore or release, and a reason, are required'; end if;
  select * into v_h from pipeline.course_remediation_holds where course_id = p_course and lifted_at is null for update;
  if v_h.id is null then raise exception 'no open hold for course %', p_course; end if;
  update pipeline.course_remediation_holds set lifted_at = now(), lifted_by = current_user, lift_mode = p_mode, lift_reason = p_reason where id = v_h.id;
  if p_mode = 'restore' then
    v_p := v_h.before->'page';
    update pipeline.coverage_course_pages set status = v_p->>'status', next_read_at = (v_p->>'next_read_at')::timestamptz
     where course_id = p_course and url = v_h.url and status = 'mismatch';
    if not found then raise exception 'restore: the binding of % is no longer the remediated page; nothing restored', p_course; end if;
    update catalogue.course_links l set status = 'active', is_primary = coalesce((b->>'is_primary')::boolean, l.is_primary), updated_at = now()
      from jsonb_array_elements(v_h.before->'official_links') b
     where l.id = (b->>'id')::uuid and b->>'status' = 'active' and l.status = 'unverified';
    insert into search.refresh_requests(requested_by) values ('binding remediation SS-007: hold ' || v_h.id || ' restored');
    -- remove only the rejection this remediation added (none was removed if it existed before)
    if not coalesce((v_h.before->>'rejected_before')::boolean, false) then
      delete from pipeline.page_rejections r where r.course_id = p_course and r.url = v_h.url and r.source = 'binding_remediation' and r.signals->>'hold_id' = v_h.id::text;
    end if;
  end if;
  return jsonb_build_object('hold_id', v_h.id, 'course_id', p_course, 'mode', p_mode,
                            'note', case p_mode when 'restore' then 'binding and official link restored; job course-url-fill fills courses.course_url again on its next run'
                                                else 'hold lifted; the course returns to the normal search lanes and the rejected page stays rejected' end);
end $function$;
revoke all on function security.binding_remediation_lift_v1(uuid, text, text) from public, anon, authenticated, service_role;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_remediation_holds', 'Pipeline', 'Coverage', 'SS-007: binding remediation hold, audit and rollback record', 'active', '{}', '20261031030000'),
 ('function', 'security.course_held_v1', 'Pipeline', 'Coverage', 'SS-007: is a course under an open binding remediation hold', 'active', '{}', '20261031030000'),
 ('function', 'security.binding_remediation_apply_v1', 'Pipeline', 'Coverage', 'SS-007: governed, count-guarded re-role of reviewed bindings (Platform Admin run)', 'active', '{}', '20261031030000'),
 ('function', 'security.binding_remediation_lift_v1', 'Pipeline', 'Coverage', 'SS-007: lift a remediation hold (restore or release)', 'active', '{}', '20261031030000')
on conflict do nothing;

-- post-check
do $$
begin
  if exists (select 1 from pipeline.course_remediation_holds) then raise exception 'SS-007 post-check: no hold may exist when this ships'; end if;
  if has_function_privilege('authenticated', 'security.binding_remediation_apply_v1(uuid,jsonb,integer,text,text)', 'execute')
     or has_function_privilege('service_role', 'security.binding_remediation_apply_v1(uuid,jsonb,integer,text,text)', 'execute')
     or has_function_privilege('authenticated', 'security.binding_remediation_lift_v1(uuid,text,text)', 'execute') then
    raise exception 'SS-007 post-check: remediation functions must be Platform Admin only'; end if;
  if (select prosrc from pg_proc where oid = 'security.coverage_ai_match_prepare_v1(integer,integer)'::regprocedure) !~ 'course_held_v1\(co\.id\)[\s\S]*course_held_v1\(co\.id\)' then
    raise exception 'SS-007 post-check: AI match preparation does not check the hold in both places'; end if;
  if not exists (select 1 from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'remediation.max_batch_courses') then
    raise exception 'SS-007 post-check: setting remediation.max_batch_courses missing'; end if;
end $$;
