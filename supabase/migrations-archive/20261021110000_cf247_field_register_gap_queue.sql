-- CF-247 (21 Oct 2026). Platform Admin 07:30: "Platform needs to keep working and cross checking on missing data fields. while majority of
-- the data fields are catered by adapters, rest of every fields should have cross check and mechanism to enrich the data ongoing. Work
-- only or queue should fill them with checks. Also coverage menu should details all data fields filled together not the top 7, as non etl
-- based countries we need to fetch data from their websites and need to have same attributes completeness across the board."
-- Choices: "Stored pages + AI, small reads (Recommended)", "When page changes, or 60 days (Recommended)", "All on Coverage; queue for
-- readable ones (Recommended)".
--   1 pipeline.field_register: every course and provider field the platform holds (15 course, 9 provider), its label, group, how it is
--     filled (register, coverage pipeline, Enrich fields, or no reader yet) and its target share (80%, changed on Coverage by the Platform
--     Admin with a reason). The same fields and targets apply to every country; the sources stay per country (Field sources).
--   2 Coverage by attribute (security.course_coverage_build_v1, hourly) covers every course field in the register instead of 7. Fields the
--     Enrich fields job fills show where that work is: In the fill queue, In review, Page read and not stated (re-checked later), or the
--     page stage. Fields with no reader yet show "No reader yet". Duration, campus and registered tuition are register (Layer 1) values in
--     Australia only; elsewhere they are filled like any other field. security.admin_course_coverage_read takes its attribute list from the
--     register (two lines, md5-guarded).
--   3 Standing gap queue (job field-gap-queue, every 6 hours): when the previous standing run has finished, one Enrich fields task
--     ("Fill the gaps", lane enrich-standing, beside any task a person starts) is made for every active course and provider missing an
--     Enrich field, except: values locked by hand, items waiting for a person, and items whose page did not state the value less than
--     gaps.recheck_days (60) ago unless the page has been read again since. Sources, AI guard and model are those of Enrich fields; new page
--     reads by the standing task stop at gaps.scraper_reads_per_day (200) a day (one line added to security.enrich_fields_slice_v1,
--     md5-guarded). On and off on Coverage (Platform Admin, with a reason); pipeline.field_gap_queue_control.
--     The flag unit (15 Oct 2026) already holds an item whose page did not state the value until the page is read again with new content;
--     that soft hold now ends after gaps.recheck_days as well (security.enrich_item_held_v1, used by the item gate and the queue). Hard
--     holds (raised flags, a person's hold) stay until released on Layer 2/3 › Flags.
--   4 Cross-check (each run of field-gap-queue): a held duration, study level or delivery mode that differs from the latest adapter reading of
--     the course page is recorded in pipeline.field_crosscheck_findings with the page wording; nothing is overwritten. A person keeps the
--     held value (Dismiss) or takes the page value (Accept: written and locked by hand) on Coverage. Findings whose values agree again close
--     themselves. Durations differ when they are more than crosscheck.duration_tolerance_pct (10%) apart in weeks; ranges ("1-2 years")
--     and semesters are not compared.
--   5 public.admin_field_coverage: the register, every field by country, provider fields, the standing queue and the cross-check findings.
-- Replaces: security.course_coverage_build_v1() (whole: register attributes and enrich states); security.admin_course_coverage_read
--   (attribute list and state list only); security.enrich_fields_slice_v1 (one line: the standing task's daily read limit);
--   security.field_enrich_items_gate_v1() (whole: the hold moves to security.enrich_item_held_v1 and its soft part ends after the set days)
-- Retires: the fixed 7-attribute list in admin_course_coverage_read and the Coverage page (now from the register)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"security.course_coverage_build_v1()": "ebbadece5cdf5c546f8fa92c6fa2c497",
                              "security.admin_course_coverage_read(text,jsonb)": "9bbee980e58adbbd6f71a81121ce69f5",
                              "security.enrich_fields_slice_v1(uuid,integer)": "e1d5153fd73e9688c8652b39aa3182df",
                              "security.field_enrich_items_gate_v1()": "6a12c0ee4eef29803e073695c7dd5c18"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 Field register -------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_register (
  field text primary key,
  level text not null check (level in ('course', 'provider')),
  label text not null,
  grp text not null,
  sort int not null,
  reader text not null check (reader in ('register', 'coverage', 'enrich', 'none')),
  fills text not null,
  target_pct numeric not null default 80 check (target_pct between 0 and 100),
  active boolean not null default true,
  reason text,
  updated_by uuid,
  updated_at timestamptz not null default now());
alter table pipeline.field_register enable row level security;
comment on table pipeline.field_register is 'CF-247 21 Oct 2026: every course and provider field the platform holds, how it is filled (register, coverage pipeline, Enrich fields, or no reader yet) and its target share. Coverage › Attributes, the coverage build and the standing gap queue read it. The target is changed on Coverage by the Platform Admin with a reason.';

insert into pipeline.field_register(field, level, label, grp, sort, reader, fills, reason) values
 ('official_url', 'course', 'Official course page', 'Course page', 10, 'coverage', 'Course-page search and matching (coverage pipeline)', 'CF-247 21 Oct 2026: starting register'),
 ('level', 'course', 'Study level', 'Study', 20, 'enrich', 'Register; adapter; AI from the title (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('field_of_study', 'course', 'Field of study', 'Study', 30, 'enrich', 'Register (Australia); AI from the title (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('duration', 'course', 'Duration', 'Study', 40, 'enrich', 'Register (Australia); adapter; AI reads the stored page (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('delivery', 'course', 'Delivery mode', 'Study', 50, 'enrich', 'Register; adapter; AI reads the stored page (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('campus', 'course', 'Campus linked', 'Location', 60, 'enrich', 'Register (Australia); campus list per university (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('campus_city', 'course', 'Campus city', 'Location', 70, 'enrich', 'The linked campus''s city (campus list per university)', 'CF-247 21 Oct 2026: starting register'),
 ('international', 'course', 'Open to international students', 'Entry', 80, 'enrich', 'Register (Australia); institution rule; adapter; AI (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('provider_tuition', 'course', 'Provider tuition (fee year)', 'Cost', 90, 'coverage', 'Adapters, central fee pages, page reader (coverage pipeline)', 'CF-247 21 Oct 2026: starting register'),
 ('registered_tuition', 'course', 'Registered tuition (register)', 'Cost', 100, 'register', 'CRICOS register (Australia only)', 'CF-247 21 Oct 2026: starting register'),
 ('intakes', 'course', 'Intakes / start dates', 'Dates', 110, 'coverage', 'Adapters, central calendars, page reader (coverage pipeline)', 'CF-247 21 Oct 2026: starting register'),
 ('deadline', 'course', 'Application deadline', 'Dates', 120, 'none', 'No reader yet (next release)', 'CF-247 21 Oct 2026: starting register'),
 ('english', 'course', 'English requirements', 'Entry', 130, 'coverage', 'Adapters, central English pages, page reader (coverage pipeline)', 'CF-247 21 Oct 2026: starting register'),
 ('academic_entry', 'course', 'Academic entry requirements', 'Entry', 140, 'none', 'No reader yet (next release)', 'CF-247 21 Oct 2026: starting register'),
 ('description', 'course', 'Course description', 'Course page', 150, 'none', 'No reader yet (next release)', 'CF-247 21 Oct 2026: starting register'),
 ('p_website', 'provider', 'Website', 'Provider', 210, 'coverage', 'Register; website search', 'CF-247 21 Oct 2026: starting register'),
 ('p_address', 'provider', 'Street address', 'Provider', 220, 'enrich', 'Register (Australia); contact or home page (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('p_campuses', 'provider', 'Campuses', 'Provider', 230, 'enrich', 'Register (Australia); campus list from course pages (Enrich fields)', 'CF-247 21 Oct 2026: starting register'),
 ('p_type', 'provider', 'Institution type', 'Provider', 240, 'register', 'Register and institution type rules', 'CF-247 21 Oct 2026: starting register'),
 ('p_international', 'provider', 'Enrols international students', 'Provider', 250, 'register', 'Register rules (CRICOS, NZQA page, IRCC DLI list)', 'CF-247 21 Oct 2026: starting register'),
 ('p_logo', 'provider', 'Logo', 'Provider', 260, 'coverage', 'Website (coverage sweep)', 'CF-247 21 Oct 2026: starting register'),
 ('p_contact', 'provider', 'Phone or email', 'Provider', 270, 'coverage', 'Register; contact page', 'CF-247 21 Oct 2026: starting register'),
 ('p_scholarships', 'provider', 'Scholarships', 'Provider', 280, 'coverage', 'Scholarship discovery and AI extraction', 'CF-247 21 Oct 2026: starting register'),
 ('p_description', 'provider', 'Description', 'Provider', 290, 'none', 'No reader yet (next release)', 'CF-247 21 Oct 2026: starting register')
on conflict (field) do nothing;

-- 2 Settings and control ------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'gaps.recheck_days', 'Check a field the page did not state again after', 'A field the course page did not state is queued again after this many days, or sooner when the page is read again.', 'number', to_jsonb(60), 7, 365, 'days', 104, 'CF-247, Platform Admin 21 Oct 2026 "When page changes, or 60 days (Recommended)"', 'Re-read and retry', 'job field-gap-queue'),
 ('pipeline', 'gaps.items_per_run', 'Standing gap queue: items per run', 'The most course and provider fields one standing Fill the gaps task takes; the rest wait for the next run.', 'number', to_jsonb(30000), 1000, 200000, 'items', 105, 'CF-247, Platform Admin 21 Oct 2026 "Platform needs to keep working and cross checking on missing data fields"', 'Re-read and retry', 'job field-gap-queue'),
 ('pipeline', 'gaps.scraper_reads_per_day', 'Standing gap queue: new page reads a day', 'New page reads (Firecrawl) the standing Fill the gaps task may ask for in a day; stored pages and the AI are used first.', 'number', to_jsonb(200), 0, 3000, 'reads', 106, 'CF-247, Platform Admin 21 Oct 2026 "Stored pages + AI, small reads (Recommended)"', 'Re-read and retry', 'job field-gap-queue; Enrich fields tasks (standing)'),
 ('pipeline', 'crosscheck.duration_tolerance_pct', 'Cross-check: durations differ when more than', 'A held duration and the course page''s duration are recorded as different when they are this far apart (in weeks).', 'number', to_jsonb(10), 0, 100, '%', 107, 'CF-247, Platform Admin 21 Oct 2026 "rest of every fields should have cross check"', 'Re-read and retry', 'job field-gap-queue (cross-check)')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.field_gap_queue_control (
  id int primary key default 1 check (id = 1),
  enabled boolean not null default true,
  owner uuid not null,
  reason text not null,
  updated_at timestamptz not null default now());
alter table pipeline.field_gap_queue_control enable row level security;
comment on table pipeline.field_gap_queue_control is 'CF-247 21 Oct 2026: the standing gap queue switch (job field-gap-queue). owner = the Platform Admin who last switched it; the standing Fill the gaps tasks are recorded as theirs. Changed on Coverage with a reason.';
insert into pipeline.field_gap_queue_control(id, enabled, owner, reason)
select 1, true, ur.user_id, 'CF-247 21 Oct 2026: Platform Admin "Platform needs to keep working and cross checking on missing data fields"'
  from security.user_roles ur join security.roles r on r.code = ur.role_code
 where r.rank = 6 and r.status = 'active' and (ur.expires_at is null or ur.expires_at > now())
 order by ur.user_id limit 1
on conflict (id) do nothing;
do $c$ begin if not exists (select 1 from pipeline.field_gap_queue_control) then raise exception 'no Platform Admin to own the standing queue'; end if; end $c$;

-- 3 Cross-check findings ------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.field_crosscheck_findings (
  id bigserial primary key,
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  provider_id uuid not null,
  field text not null,
  held_value jsonb not null,
  page_value jsonb not null,
  source text not null,
  quote text,
  evidence_id uuid,
  state text not null default 'open' check (state in ('open', 'dismissed', 'accepted', 'resolved')),
  found_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid,
  note text,
  unique (course_id, field, page_value));
alter table pipeline.field_crosscheck_findings enable row level security;
create index if not exists idx_field_crosscheck_open on pipeline.field_crosscheck_findings(field) where state = 'open';
comment on table pipeline.field_crosscheck_findings is 'CF-247 21 Oct 2026: a held course value that differs from a newer reading of the course page (field, held value, page value, wording, evidence). Nothing is overwritten: a person keeps the held value (dismissed) or takes the page value (accepted, written and locked by hand) on Coverage; an open finding whose values agree again is resolved by the next run.';

create or replace function security.field_crosscheck_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_new int; v_closed int; v_tol numeric := security.pipeline_num_v1('crosscheck.duration_tolerance_pct', 10);
begin
  -- the latest adapter reading of each course page (the same reading Enrich fields uses), compared with the held value
  insert into pipeline.field_crosscheck_findings(course_id, provider_id, field, held_value, page_value, source, quote, evidence_id)
  select y.id, y.provider_id, y.field, y.held_value, y.page_value, 'adapter', left(y.txt, 300), y.ev
    from (
      select x.id, x.provider_id, f.field, f.held_value, f.page_value, f.txt, x.ev, f.differs
        from (select c.id, c.provider_id, c.duration_value, c.duration_unit, c.study_level_id, c.delivery_mode,
                     (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = c.id) ev,
                     coalesce((select r.fields->'extra' from pipeline.uni_adapter_results r where r.course_id = c.id order by r.at desc limit 1), '{}'::jsonb)
                     || coalesce((select g.candidates->'adapter_extra' from pipeline.coverage_course_pages g
                                   where g.course_id = c.id and g.read_status = 'read' and g.identity_basis is not null), '{}'::jsonb) ex
                from catalogue.courses c where c.lifecycle_status = 'active') x
        cross join lateral (
          select 'duration' field, jsonb_build_object('value', x.duration_value, 'unit', x.duration_unit) held_value, d page_value, x.ex->>'duration' txt,
                 abs(w1 - w2) * 100 > v_tol * greatest(w1, w2) differs
            from (select security.enrich_parse_duration_v1(nullif(btrim(x.ex->>'duration'), '')) d) p,
                 lateral (select case x.duration_unit when 'years' then x.duration_value * 52 when 'months' then x.duration_value * 52 / 12 when 'weeks' then x.duration_value end w1,
                                 case p.d->>'unit' when 'years' then (p.d->>'value')::numeric * 52 when 'months' then (p.d->>'value')::numeric * 52 / 12 when 'weeks' then (p.d->>'value')::numeric end w2) w
           where p.d is not null and x.duration_value is not null and w.w1 > 0 and w.w2 > 0
             and coalesce(x.ex->>'duration', '') !~* '\d\s*(-|–|to|or)\s*\d'
          union all
          select 'level', jsonb_build_object('level_id', x.study_level_id, 'name', (select l.name from ref.study_levels l where l.id = x.study_level_id)),
                 jsonb_build_object('level_id', p.l, 'name', (select l.name from ref.study_levels l where l.id = p.l)), x.ex->>'study_level', p.l <> x.study_level_id
            from (select security.enrich_parse_level_v1(nullif(btrim(x.ex->>'study_level'), '')) l) p
           where p.l is not null and x.study_level_id is not null
          union all
          select 'delivery', jsonb_build_object('mode', x.delivery_mode), jsonb_build_object('mode', p.m), x.ex->>'mode', p.m <> x.delivery_mode
            from (select security.enrich_parse_delivery_v1(left(nullif(btrim(x.ex->>'mode'), ''), 120)) m) p
           where p.m is not null and nullif(btrim(x.delivery_mode), '') is not null) f
       where x.ex <> '{}'::jsonb) y
   where y.differs
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = y.id and l.field in (y.field, 'all'))
  on conflict (course_id, field, page_value) do nothing;
  get diagnostics v_new = row_count;
  -- open findings whose held value now equals the page value (or the course left the catalogue) close themselves
  update pipeline.field_crosscheck_findings f set state = 'resolved', decided_at = now(), note = 'the held value now agrees with the page'
    from catalogue.courses c
   where f.state = 'open' and c.id = f.course_id
     and case f.field when 'level' then c.study_level_id = (f.page_value->>'level_id')::uuid
                      when 'delivery' then c.delivery_mode = f.page_value->>'mode'
                      when 'duration' then c.duration_value = (f.page_value->>'value')::numeric and c.duration_unit = f.page_value->>'unit' else false end;
  get diagnostics v_closed = row_count;
  return jsonb_build_object('new', v_new, 'resolved', v_closed, 'open', (select count(*) from pipeline.field_crosscheck_findings where state = 'open'));
end $function$;
revoke execute on function security.field_crosscheck_v1() from public, anon, authenticated;

-- 4 Standing gap queue --------------------------------------------------------------------------------------------------------------
create or replace function security.gap_scraper_room_v1()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  -- new page reads asked for by standing Fill the gaps tasks since midnight (Melbourne), against the daily limit
  select (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
           where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) and 'scraper' = any (e.tried)
             and e.updated_at >= (date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne'))  -- fixed: the day rolls over at Melbourne midnight
         < security.pipeline_num_v1('gaps.scraper_reads_per_day', 200)
$function$;
revoke execute on function security.gap_scraper_room_v1() from public, anon, authenticated;

select pg_temp.edit_once('security.enrich_fields_slice_v1(uuid,integer)', 'e1d5153fd73e9688c8652b39aa3182df', array[
  array[$x$      continue when v_src = 'scraper' and not v_scr;
$x$, $x$      continue when v_src = 'scraper' and not v_scr;
      -- CF-247 21 Oct 2026: the standing Fill the gaps task asks for new page reads only within its daily limit
      continue when v_src = 'scraper' and coalesce((j.args->>'standing')::boolean, false) and not security.gap_scraper_room_v1();
$x$]]);

-- the flag unit's hold (15 Oct 2026), now in one place for the item gate and the standing queue; a soft "page did not state it" flag holds
-- only for gaps.recheck_days (Platform Admin 21 Oct 2026 "When page changes, or 60 days")
create or replace function security.enrich_item_held_v1(p_course uuid, p_field text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (select 1 from pipeline.enrichment_flags f
                  where f.entity = 'course' and f.entity_key = p_course::text and f.field in (p_field, '')
                    and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                         or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                             and f.flagged_at > now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int)
                             and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = p_course and g.evidence_id is not null
                                               and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at))))
$function$;
revoke execute on function security.enrich_item_held_v1(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.field_enrich_items_gate_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.course_id is null then return new; end if;
  -- held, or tried on the same input less than gaps.recheck_days ago: not queued (CF-247 21 Oct 2026: the hold is security.enrich_item_held_v1)
  if security.enrich_item_held_v1(new.course_id, new.field) then return null; end if;
  return new;
end $function$;

create or replace function security.field_gap_queue_tick_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare c pipeline.field_gap_queue_control%rowtype; v_job uuid; v_n int; v_x jsonb; v_fields text[];
        v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int; v_cap int := security.pipeline_num_v1('gaps.items_per_run', 30000)::int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and coalesce(security.current_role_rank(), 0) < 4 then
    raise exception 'Pipeline Operator role or above required' using errcode = '42501';
  end if;
  v_x := jsonb_build_object('crosscheck', security.field_crosscheck_v1());
  select * into c from pipeline.field_gap_queue_control where id = 1;
  if not coalesce(c.enabled, false) then return v_x || jsonb_build_object('queue', 'off'); end if;
  if exists (select 1 from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) and j.state in ('queued', 'running', 'paused')) then
    return v_x || jsonb_build_object('queue', 'previous run still open');
  end if;
  v_fields := array(select f.field from security.enrich_fields_v1() f);
  drop table if exists _gap;
  create temp table _gap(provider_id uuid, course_id uuid, field text, pri int) on commit drop;
  insert into _gap
  with miss as (
    select c2.id course_id, c2.provider_id, f.x field
      from catalogue.courses c2 cross join unnest(v_fields) f(x)
     where c2.lifecycle_status = 'active' and f.x not in ('provider_address', 'campus_list')
       and case f.x when 'campus' then not exists (select 1 from catalogue.course_campuses x where x.course_id = c2.id)
                    when 'duration' then c2.duration_value is null when 'level' then c2.study_level_id is null
                    when 'delivery' then nullif(btrim(c2.delivery_mode), '') is null when 'field_of_study' then c2.primary_field_id is null
                    when 'international' then c2.open_to_international is null else false end
    union all
    select null::uuid, p.id, 'provider_address'
      from catalogue.providers p
     where 'provider_address' = any (v_fields) and nullif(btrim(p.address_line1), '') is null and coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.courses c3 where c3.provider_id = p.id and c3.lifecycle_status = 'active')),
  last as (
    select distinct on (e.provider_id, e.course_id, e.field) e.provider_id, e.course_id, e.field, e.state, e.updated_at
      from pipeline.field_enrich_items e where e.field <> 'campus_list'
     order by e.provider_id, e.course_id, e.field, e.id desc)
  select m.provider_id, m.course_id, m.field,
         case when l.state is null then 1
              when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at) then 0
              else 2 end
    from miss m
    left join last l on l.provider_id = m.provider_id and l.course_id is not distinct from m.course_id and l.field = m.field
   where not exists (select 1 from pipeline.manual_locks k where k.entity = case when m.course_id is null then 'provider' else 'course' end
                       and k.entity_id = coalesce(m.course_id, m.provider_id) and k.field in (m.field, 'all'))
     and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')   -- being worked on, or waiting for a person
     and (l.state is null or l.state = 'filled'                                          -- never tried, or filled and since emptied
          or l.updated_at < now() - make_interval(days => v_days)                        -- not stated: checked again after the set days
          or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.course_id and g.read_at > l.updated_at))  -- or once the page is read again
   order by 4, m.course_id
   limit v_cap;
  delete from _gap g where g.course_id is not null and security.enrich_item_held_v1(g.course_id, g.field);  -- the item gate would not queue it
  select count(*) into v_n from _gap;
  if v_n = 0 then return v_x || jsonb_build_object('queue', 'nothing due'); end if;
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich-standing', 'queued', 'Fill the gaps · all countries (standing)',
          jsonb_build_object('countries', to_jsonb(security.catalogue_country_codes_v1()), 'provider_ids', '[]'::jsonb, 'fields', to_jsonb(v_fields),
                             'ai', true, 'scraper', true, 'standing', true),
          jsonb_build_object('done', 0, 'total', 0), c.owner, 'Standing gap queue (job field-gap-queue): ' || c.reason, 'All countries')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field) select v_job, g.provider_id, g.course_id, g.field from _gap g on conflict do nothing;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state)
  select distinct v_job, e.provider_id, null::uuid, 'campus_list', 'waiting' from pipeline.field_enrich_items e where e.job_id = v_job and e.field = 'campus'
  on conflict do nothing;
  select count(*) into v_n from pipeline.field_enrich_items where job_id = v_job;
  update pipeline.admin_jobs set progress = jsonb_build_object('done', 0, 'total', v_n) where id = v_job;
  insert into pipeline.admin_job_events(job_id, note, detail) values (v_job, v_n || ' item(s) to settle (standing gap queue)',
    (select jsonb_object_agg(field, n) from (select field, count(*) n from pipeline.field_enrich_items where job_id = v_job group by 1) z));
  return v_x || jsonb_build_object('queue', 'started', 'job_id', v_job, 'items', v_n);
end $function$;
revoke execute on function security.field_gap_queue_tick_v1() from public, anon, authenticated;

-- 5 Coverage by attribute: every course field in the register -------------------------------------------------------------------
CREATE OR REPLACE FUNCTION security.course_coverage_build_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare v_n int; v_t0 timestamptz:=clock_timestamp();
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  create temp table _c on commit drop as
    select co.id course_id, co.provider_id, co.duration_value, co.study_level_id, co.primary_field_id, co.delivery_mode, co.open_to_international,
           nullif(btrim(co.description),'') is not null has_description, k.iso_alpha2::text country_code
      from catalogue.courses co join catalogue.providers p on p.id=co.provider_id join ref.countries k on k.id=p.country_id
     where co.lifecycle_status='active'; -- Decision 213: every country
  create temp table _tier on commit drop as
    select provider_id, case when rk<=10 then 'top_10' when rk<=40 then 'top_11_40' when rk<=100 then 'top_41_100' else 'rest' end tier
      from (select provider_id, row_number() over (partition by min(country_code) order by count(*) desc, provider_id) rk from _c group by provider_id) x; -- tiers within each country
  create temp table _site on commit drop as
    select t.provider_id from _tier t join catalogue.providers p on p.id=t.provider_id
     where nullif(btrim(p.website),'') is not null or exists(select 1 from pipeline.provider_discovery_links l where l.provider_id=t.provider_id);
  create temp table _found on commit drop as
    select distinct course_id from pipeline.layer2_course_discovery_candidates where selected and course_id is not null;
  create temp table _read on commit drop as
    select entity_id course_id, bool_or(status in ('resolved_l2','layer3_required')) read_ok, bool_or(status='blocked') blocked
      from pipeline.layer2_run_items where entity_type='course' group by entity_id;
  create temp table _sw on commit drop as
    select course_id, status, read_status, identity_basis,
           (read_status='read' and identity_basis='cricos_code') verified,
           coalesce((candidates->'fee'->>'value') is not null,false) c_tuition,
           coalesce(candidates->'english' ? 'ielts_overall' or candidates->'english' ? 'pte_overall' or candidates->'english' ? 'toefl_overall',false) c_english,
           coalesce(jsonb_array_length(candidates->'intakes')>0,false) c_intakes
      from pipeline.coverage_course_pages;
  create temp table _val on commit drop as
    select c.course_id,
      exists(select 1 from catalogue.course_links l where l.course_id=c.course_id and l.status='active' and l.link_type='official_course') url,
      exists(select 1 from catalogue.course_fees f where f.course_id=c.course_id and f.status='active' and f.fee_type='provider_current_tuition') tuition,
      exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.course_id and e.status='active') english,
      exists(select 1 from catalogue.course_intakes i where i.course_id=c.course_id and coalesce(i.status,'active')='active') intakes,
      exists(select 1 from catalogue.course_fees f where f.course_id=c.course_id and f.status='active' and f.fee_type='tuition') reg_tuition,
      exists(select 1 from catalogue.course_campuses cc where cc.course_id=c.course_id) campus,
      -- CF-247 21 Oct 2026: the other course fields of the field register
      exists(select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id=cc.campus_id where cc.course_id=c.course_id and nullif(btrim(k.city),'') is not null) campus_city,
      exists(select 1 from catalogue.course_intakes i where i.course_id=c.course_id and coalesce(i.status,'active')='active' and i.application_deadline is not null) deadline,
      exists(select 1 from catalogue.course_academic_options a where a.course_id=c.course_id) academic
    from _c c;
  create temp table _l4 on commit drop as
    select entity_id course_id, case when field_code in ('official_course_url') then 'official_url'
                                     when field_code in ('provider_current_tuition_validation','provider_current_tuition') then 'provider_tuition'
                                     when field_code ilike '%english%' then 'english' when field_code ilike '%intake%' then 'intakes' end attribute
      from pipeline.layer4_review_items where entity_type='course' and status='pending'
    union
    select entity_id, case when task_class='provider_current_tuition_validation' then 'provider_tuition' when task_class ilike '%english%' then 'english'
                           when task_class ilike '%intake%' then 'intakes' when task_class ilike '%url%' then 'official_url' end
      from pipeline.layer3_work_items where entity_type='course' and status='layer4_required';
  create temp table _l3 on commit drop as
    select entity_id course_id, case when task_class='provider_current_tuition_validation' then 'provider_tuition' when task_class ilike '%english%' then 'english'
                                     when task_class ilike '%intake%' then 'intakes' when task_class ilike '%url%' then 'official_url' end attribute
      from pipeline.layer3_work_items where entity_type='course' and status in ('pending','reserved','failed','retry');
  -- CF-247 21 Oct 2026: where the Enrich fields work is for each course and field (the latest item, any task)
  create temp table _ei on commit drop as
    select distinct on (course_id, field) course_id, field, state from pipeline.field_enrich_items where course_id is not null order by course_id, field, id desc;
  create temp table _reg on commit drop as select field attribute, reader from pipeline.field_register where level='course' and active;

  truncate pipeline.course_attribute_coverage;
  insert into pipeline.course_attribute_coverage(course_id,provider_id,attribute,state,tier,computed_at,country_code)
  select c.course_id, c.provider_id, a.attribute,
    case
      when a.l1 then case when a.has then 'admitted' else 'missing_l1' end
      when a.has then 'admitted'
      when g.reader='none' then 'no_reader'
      when g.reader='enrich' and ei.state in ('queued','waiting','ai','leased') then 'in_queue'
      when g.reader='enrich' and ei.state='review' then 'in_review'
      when g.reader='enrich' and ei.state in ('skipped','failed') then 'not_on_page'
      when g.reader='enrich' then case when r.blocked or sw.read_status in ('blocked','robots_disallowed') then 'blocked'
                                       when f.course_id is not null or v.url or sw.status='bound' or sw.verified or r.read_ok then 'page_found'
                                       when s.provider_id is not null then 'site_known' else 'no_website' end
      when exists(select 1 from _l4 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'in_review'
      when exists(select 1 from _l3 x where x.course_id=c.course_id and x.attribute=a.attribute) then 'awaiting_l3'
      when sw.verified and (a.attribute='official_url' or (a.attribute='provider_tuition' and sw.c_tuition) or (a.attribute='english' and sw.c_english) or (a.attribute='intakes' and sw.c_intakes)) then 'candidate'
      when r.read_ok or sw.verified then 'not_on_page'
      when r.blocked or sw.read_status in ('blocked','robots_disallowed') then 'blocked'
      when f.course_id is not null or v.url or sw.status='bound' then 'page_found'
      when s.provider_id is not null then 'site_known'
      else 'no_website' end,
    t.tier, now(), c.country_code
  from _c c join _val v using (course_id) join _tier t using (provider_id)
  left join _read r using (course_id) left join _found f using (course_id) left join _sw sw using (course_id) left join _site s on s.provider_id=c.provider_id
  cross join lateral (values
    ('official_url', v.url, false), ('provider_tuition', v.tuition, false), ('english', v.english, false), ('intakes', v.intakes, false),
    -- register (Layer 1) values in Australia only; registered tuition is a CRICOS value and is not counted elsewhere
    ('registered_tuition', v.reg_tuition, true), ('duration', c.duration_value is not null, c.country_code='AU'), ('campus', v.campus, c.country_code='AU'),
    ('level', c.study_level_id is not null, false), ('field_of_study', c.primary_field_id is not null, false),
    ('delivery', nullif(btrim(c.delivery_mode),'') is not null, false), ('campus_city', v.campus_city, false),
    ('international', c.open_to_international is not null, false), ('deadline', v.deadline, false), ('academic_entry', v.academic, false),
    ('description', c.has_description, false)) a(attribute, has, l1)
  join _reg g on g.attribute=a.attribute
  left join _ei ei on ei.course_id=c.course_id and ei.field=case a.attribute when 'campus_city' then 'campus' else a.attribute end
  where a.attribute<>'registered_tuition' or c.country_code='AU';
  get diagnostics v_n=row_count;

  delete from pipeline.course_coverage_daily where snapshot_date=current_date;
  insert into pipeline.course_coverage_daily(snapshot_date,attribute,state,tier,courses)
  select current_date, attribute, state, tier, count(*) from pipeline.course_attribute_coverage where country_code='AU' group by 2,3,4;
  -- Decision 213: daily counts by country
  update pipeline.course_coverage_daily_by_country set courses = 0, computed_at = now() where snapshot_date = current_date;
  insert into pipeline.course_coverage_daily_by_country(snapshot_date,country_code,attribute,state,tier,courses)
  select current_date, country_code, attribute, state, tier, count(*) from pipeline.course_attribute_coverage group by 2,3,4,5
  on conflict (snapshot_date,country_code,attribute,state,tier) do update set courses = excluded.courses, computed_at = now();
  return jsonb_build_object('rows',v_n,'courses',(select count(*) from _c),'ms',round(extract(epoch from clock_timestamp()-v_t0)*1000));
end $function$;

select pg_temp.edit_once('security.admin_course_coverage_read(text,jsonb)', '9bbee980e58adbbd6f71a81121ce69f5', array[
  array[$x$  c_attrs constant text[]:=array['official_url','provider_tuition','english','intakes','registered_tuition','duration','campus'];$x$,
        $x$  -- CF-247 21 Oct 2026: every course field of the field register, in its order (was a fixed list of 7)
  c_attrs text[]:=array(select f.field from pipeline.field_register f where f.level='course' and f.active order by f.sort);$x$],
  array[$x$unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','blocked','page_found','site_known','no_website','missing_l1']) s$x$,
        $x$unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','in_queue','blocked','page_found','site_known','no_website','missing_l1','no_reader']) s$x$]]);

-- 6 Coverage › Attributes: every field, the standing queue and the cross-check ------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_field_coverage(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_cc text := upper(nullif(btrim(coalesce(p_args->>'country', '')), ''));
        v_pid uuid := nullif(p_args->>'provider', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', '')); v_f pipeline.field_crosscheck_findings%rowtype;
        v_job pipeline.admin_jobs%rowtype;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if p_action = 'overview' then
    select * into v_job from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) order by j.created_at desc limit 1;
    return jsonb_build_object(
      'register', (select jsonb_agg(jsonb_build_object('field', r.field, 'level', r.level, 'label', r.label, 'group', r.grp, 'reader', r.reader, 'fills', r.fills,
                                                     'target_pct', r.target_pct, 'reason', r.reason, 'updated_at', r.updated_at) order by r.sort)
                     from pipeline.field_register r where r.active),
      -- every course field by country (the hourly coverage build); provider fields counted now
      'courses_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', x.country_code, 'field', x.attribute, 'total', x.total, 'filled', x.filled,
                                                                        'in_queue', x.in_queue, 'not_stated', x.not_stated, 'in_review', x.in_review)), '[]'::jsonb)
                               from (select a.country_code, a.attribute, count(*) total, count(*) filter (where a.state = 'admitted') filled,
                                            count(*) filter (where a.state = 'in_queue') in_queue, count(*) filter (where a.state = 'not_on_page') not_stated,
                                            count(*) filter (where a.state in ('in_review', 'candidate', 'awaiting_l3')) in_review
                                       from pipeline.course_attribute_coverage a
                                      where (v_cc is null or a.country_code = v_cc) and (v_pid is null or a.provider_id = v_pid) group by 1, 2) x),
      'providers_by_country', (select coalesce(jsonb_agg(jsonb_build_object('country', z.cc, 'field', z.field, 'total', z.total, 'filled', z.filled)), '[]'::jsonb)
                                 from (select p.cc, f.field, count(*) total, count(*) filter (where f.has) filled
                                         from (select p.*, security.coverage_country(p.id) cc from catalogue.providers p
                                                where coalesce(p.lifecycle_status, 'active') = 'active' and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
                                                  and (v_pid is null or p.id = v_pid)) p
                                         cross join lateral (values
                                           ('p_website', nullif(btrim(p.website), '') is not null),
                                           ('p_address', nullif(btrim(p.address_line1), '') is not null),
                                           ('p_campuses', exists (select 1 from catalogue.campuses k where k.provider_id = p.id)),
                                           ('p_type', p.provider_type_id is not null),
                                           ('p_international', p.enrols_international is not null),
                                           ('p_logo', nullif(btrim(p.logo_url), '') is not null or exists (select 1 from catalogue.provider_assets a where a.provider_id = p.id and a.asset_type = 'logo')),
                                           ('p_contact', nullif(btrim(p.phone), '') is not null or nullif(btrim(p.email), '') is not null),
                                           ('p_scholarships', exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = 'active')),
                                           ('p_description', nullif(btrim(p.description), '') is not null)) f(field, has)
                                        where v_cc is null or p.cc = v_cc
                                        group by 1, 2) z),
      'computed_at', (select max(computed_at) from pipeline.course_attribute_coverage),
      'queue', jsonb_build_object(
        'enabled', (select enabled from pipeline.field_gap_queue_control where id = 1),
        'switched', (select jsonb_build_object('reason', reason, 'at', updated_at) from pipeline.field_gap_queue_control where id = 1),
        'schedule', (select j.schedule from cron.job j where j.jobname = 'field-gap-queue'),
        'last_tick', (select jsonb_build_object('at', d.start_time, 'status', d.status, 'message', left(d.return_message, 300)) from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                       where j.jobname = 'field-gap-queue' order by d.start_time desc limit 1),
        'recheck_days', security.pipeline_num_v1('gaps.recheck_days', 60), 'items_per_run', security.pipeline_num_v1('gaps.items_per_run', 30000),
        'reads_per_day', security.pipeline_num_v1('gaps.scraper_reads_per_day', 200),
        'reads_today', (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
                         where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false) and 'scraper' = any (e.tried)
                           and e.updated_at >= (date_trunc('day', now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne')),
        'ai_spent_today_usd', (select x.spent from security.ai_spend_today_v1() x where x.use = 'enrich_fields'),
        'ai_guard_usd', (select (s.value #>> '{}')::numeric from pipeline.platform_toolset_settings s where s.toolset_key = 'openrouter' and s.key = 'guard_enrich_fields'),
        'job', case when v_job.id is null then null else jsonb_build_object('id', v_job.id, 'state', v_job.state, 'title', v_job.title, 'progress', v_job.progress,
                     'created_at', v_job.created_at, 'finished_at', v_job.finished_at,
                     'by_field', (select jsonb_object_agg(field, s) from (select field, jsonb_object_agg(state, n) s from (
                                    select e.field, e.state, count(*) n from pipeline.field_enrich_items e where e.job_id = v_job.id group by 1, 2) a group by field) b)) end,
        'runs', (select count(*) from pipeline.admin_jobs j where j.kind = 'enrich_fields' and coalesce((j.args->>'standing')::boolean, false)),
        'filled_7d', (select count(*) from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
                       where coalesce((j.args->>'standing')::boolean, false) and e.state = 'filled' and e.updated_at > now() - interval '7 days')),
      'crosscheck', (select coalesce(jsonb_agg(jsonb_build_object('field', field, 'state', state, 'n', n)), '[]'::jsonb)
                       from (select x.field, x.state, count(*) n from pipeline.field_crosscheck_findings x
                              where (v_cc is null or security.coverage_country(x.provider_id) = v_cc) and (v_pid is null or x.provider_id = v_pid) group by 1, 2) y),
      'can_decide', v_rank >= 4, 'can_manage', v_rank >= 6);
  elsif p_action = 'findings' then
    return jsonb_build_object('items', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (
      select x.id, x.field, x.held_value, x.page_value, x.source, x.quote, x.state, x.found_at, x.course_id, c.canonical_title course, coalesce(p.display_name, p.canonical_name) provider,
             security.coverage_country(x.provider_id) country
        from pipeline.field_crosscheck_findings x join catalogue.courses c on c.id = x.course_id join catalogue.providers p on p.id = x.provider_id
       where x.state = coalesce(nullif(p_args->>'state', ''), 'open') and (nullif(p_args->>'field', '') is null or x.field = p_args->>'field')
         and (v_cc is null or security.coverage_country(x.provider_id) = v_cc) and (v_pid is null or x.provider_id = v_pid)
       order by coalesce(p.display_name, p.canonical_name), c.canonical_title, x.field
       limit least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200) offset greatest(coalesce((p_args->>'offset')::int, 0), 0)) r));
  elsif p_action = 'finding_decide' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    select * into v_f from pipeline.field_crosscheck_findings where id = (p_args->>'id')::bigint for update;
    if v_f.id is null or v_f.state <> 'open' then raise exception 'this difference is no longer open'; end if;
    if p_args->>'decision' = 'dismiss' then
      update pipeline.field_crosscheck_findings set state = 'dismissed', decided_at = now(), decided_by = auth.uid(), note = nullif(v_reason, '') where id = v_f.id;
    elsif p_args->>'decision' = 'accept' then
      perform set_config('cf.manual_edit', 'on', true);
      update catalogue.courses c set duration_value = case when v_f.field = 'duration' then (v_f.page_value->>'value')::numeric else c.duration_value end,
             duration_unit = case when v_f.field = 'duration' then v_f.page_value->>'unit' else c.duration_unit end,
             study_level_id = case when v_f.field = 'level' then (v_f.page_value->>'level_id')::uuid else c.study_level_id end,
             delivery_mode = case when v_f.field = 'delivery' then v_f.page_value->>'mode' else c.delivery_mode end, updated_at = now()
       where c.id = v_f.course_id;
      insert into pipeline.manual_locks(entity, entity_id, field, mode, set_by) values ('course', v_f.course_id, v_f.field, 'value', auth.uid())
      on conflict (entity, entity_id, field) do update set mode = 'value', set_by = excluded.set_by, set_at = now();
      update pipeline.field_crosscheck_findings set state = 'accepted', decided_at = now(), decided_by = auth.uid(), note = nullif(v_reason, '') where id = v_f.id;
      insert into search.refresh_requests(requested_by) values ('field cross-check accepted');
    else raise exception 'decision is dismiss or accept'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_crosscheck', p_args->>'decision', v_f.field || ' ' || v_f.course_id, jsonb_build_object('held', v_f.held_value, 'found', v_f.page_value, 'quote', v_f.quote, 'reason', v_reason), auth.uid());
    return jsonb_build_object('id', v_f.id, 'state', case when p_args->>'decision' = 'dismiss' then 'dismissed' else 'accepted' end);
  elsif p_action = 'queue_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.field_gap_queue_control set enabled = coalesce((p_args->>'enabled')::boolean, enabled), owner = auth.uid(), reason = v_reason, updated_at = now() where id = 1;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_gap_queue', case when (p_args->>'enabled')::boolean then 'on' else 'off' end, 'field-gap-queue', jsonb_build_object('reason', v_reason), auth.uid());
    return public.admin_field_coverage('overview', '{}'::jsonb);
  elsif p_action = 'target_set' then
    if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    update pipeline.field_register set target_pct = (p_args->>'target_pct')::numeric, reason = v_reason, updated_by = auth.uid(), updated_at = now()
     where field = p_args->>'field';
    if not found then raise exception 'unknown field'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('field_register', 'target', p_args->>'field', jsonb_build_object('target_pct', p_args->'target_pct', 'reason', v_reason), auth.uid());
    return public.admin_field_coverage('overview', '{}'::jsonb);
  elsif p_action = 'run_now' then
    if v_rank < 4 then raise exception 'Pipeline Operator role or above required' using errcode = '42501'; end if;
    return security.field_gap_queue_tick_v1();
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;
revoke execute on function public.admin_field_coverage(text, jsonb) from public, anon;
grant execute on function public.admin_field_coverage(text, jsonb) to authenticated;

-- 7 Job, catalogue, register --------------------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('field-gap-queue', 'Course pages', 30, 'Fill the gaps (standing queue) and cross-check', 'Every 6 hours: cross-checks held duration, level and delivery against the latest course page reading (differences listed on Coverage; nothing is overwritten); then, when the previous run has finished, starts one Enrich fields task for every active course and provider missing a field, except values locked by hand, items waiting for a person, and fields the page did not state that are not yet due again (Pipeline settings › Re-read and retry). On and off on Coverage › Attributes.', 6, false)
on conflict (jobname) do nothing;
select cron.schedule('field-gap-queue', '23 */6 * * *', $$select security.field_gap_queue_tick_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.field_register', 'Layer 2', 'Every course and provider field, how it is filled and its target share', 'active', '20261021110000'),
 ('table', 'pipeline.field_gap_queue_control', 'Layer 2', 'The standing gap queue switch and its owner', 'active', '20261021110000'),
 ('table', 'pipeline.field_crosscheck_findings', 'Layer 2', 'Held course values that differ from a newer reading of the page', 'active', '20261021110000'),
 ('function', 'security.field_gap_queue_tick_v1', 'Layer 2', 'Standing gap queue: cross-check, then one Fill the gaps task when due', 'active', '20261021110000'),
 ('function', 'security.field_crosscheck_v1', 'Layer 2', 'Cross-checks held duration, level and delivery against the latest page reading', 'active', '20261021110000'),
 ('function', 'security.enrich_item_held_v1', 'Layer 2', 'Whether a course field is held out of Enrich fields queues (flag unit)', 'active', '20261021110000'),
 ('function', 'security.gap_scraper_room_v1', 'Layer 2', 'Standing Fill the gaps task: room left in the daily page-read limit', 'active', '20261021110000'),
 ('function', 'public.admin_field_coverage', 'Layer 2', 'Coverage › Attributes: every field by country, the standing queue and the cross-check', 'active', '20261021110000'),
 ('job', 'field-gap-queue', 'Layer 2', 'Fill the gaps (standing queue) and cross-check', 'active', '20261021110000')
on conflict (kind, name) do nothing;
