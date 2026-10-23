-- CF-247 (24 Oct 2026). NZ enrichment brief item 5, Option A (Platform Admin 23 Oct 2026 20:42 "Item 5 Option A with a fourth guard";
-- consolidated NZ field-admission mandate 24 Oct 2026 00:35 "ITEM 5 BUILD (approved)"). Spec: admin repo
-- docs/platform/nz-enrichment-brief/2026-10-23-nz-brief-decisions.md section 5.
-- A course whose own page is proven gets that page's address in catalogue.courses.course_url when the field is empty, so the website
-- and Zoho can show the link. No consumer API shape change (G3): a nullable field that is already read is populated more often.
-- The four guards: 1 proven binding only (status bound, identity_basis present, read_status read, a stored copy); 2 manual locks
-- honoured (pipeline.manual_locks course/course_url, and only an empty course_url is written); 3 re-fill on binding change (a fill is
-- taken back when the page is no longer bound or its copy changed, the address emptied only when it still equals the filled value,
-- then filled again from the new binding when it qualifies); 4 30-day retraction-rate monitoring (above course_url.max_retraction_pct
-- the job pauses itself by switching course_url.fill_enabled off, logged).
-- Countries filled are a setting (course_url.fill_countries, NZ first, by the Platform Admin's mandate); the dry run shows the count
-- per country and ten sample rows before apply.
-- Replaces: nothing
-- Retires: nothing

-- 1 the fill register ------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.course_url_fills (
  course_id uuid primary key references catalogue.courses(id),
  url text not null,
  evidence_id uuid not null,
  identity_basis text not null,
  filled_at timestamptz not null default now(),
  retracted_at timestamptz,
  retract_reason text
);
comment on table pipeline.course_url_fills is 'course_url values the platform filled from a proven course-page binding (NZ brief item 5): one row per course, the page copy (evidence_id) as proof; a retraction closes the row (retracted_at, reason) and a later qualifying binding fills it again; never deleted';
create index if not exists course_url_fills_filled_at_idx on pipeline.course_url_fills (filled_at desc);
create index if not exists course_url_fills_open_idx on pipeline.course_url_fills (course_id) where retracted_at is null;
alter table pipeline.course_url_fills enable row level security;

-- 2 settings ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'course_url.fill_enabled', 'Official link: fill from the proven page',
  '1 fills an empty course link (course_url) from the course''s proven own page each night; 0 stops the job. The job sets this to 0 itself when more than Official link: most taken back of the last 30 days'' fills were taken back (logged); a person switches it back on after tightening eligibility.',
  'number', '1'::jsonb, '0', '1', 'on/off', 601, 'Official link', 'job course-url-fill; security.course_url_fill_v1', 'NZ brief item 5 Option A (Platform Admin 23 Oct 2026 20:42)'),
 ('pipeline', 'course_url.max_retraction_pct', 'Official link: most taken back',
  'Share of the last 30 days'' filled links taken back (page no longer bound or its copy changed) above which the fill job pauses itself.',
  'number', '5'::jsonb, '1', '20', '%', 602, 'Official link', 'security.course_url_fill_v1; security.course_url_retraction_30d_v1 (hourly report)', 'NZ brief item 5 Option A (Platform Admin 23 Oct 2026 20:42)'),
 ('pipeline', 'batch.course_url_fill', 'Official link: links filled a run',
  'Courses the nightly fill job (02:23 UTC) writes a link for in one run.',
  'number', '2000'::jsonb, '100', '5000', 'courses', 603, 'Job sizes', 'job course-url-fill', 'NZ brief item 5 Option A (Platform Admin 23 Oct 2026 20:42)'),
 ('pipeline', 'course_url.fill_countries', 'Official link: countries filled',
  'Course links are filled only for courses in these countries. NZ first (Platform Admin 24 Oct 2026 00:35); add AU and CA deliberately after the NZ run is reviewed.',
  'list', '["NZ"]'::jsonb, null, null, 'countries', 604, 'Official link', 'security.course_url_fill_v1', 'NZ field admission mandate (Platform Admin 24 Oct 2026 00:35)')
on conflict (toolset_key, key) do nothing;

-- 3 the 30-day retraction figure (guard 4; the hourly report prints it) -------------------------------------------------------------
create or replace function security.course_url_retraction_30d_v1() returns jsonb
language sql stable security definer set search_path = '' as $$
  with f as (select retracted_at, retract_reason from pipeline.course_url_fills where filled_at > now() - interval '30 days')
  select jsonb_build_object(
    'filled', count(*),
    'retracted', count(*) filter (where retracted_at is not null),
    'retraction_pct', round(100.0 * count(*) filter (where retracted_at is not null) / nullif(count(*), 0), 2),
    'by_reason', (select coalesce(jsonb_object_agg(coalesce(retract_reason, 'kept'), n), '{}'::jsonb) from (select retract_reason, count(*) n from f group by 1) r),
    'max_pct', security.pipeline_num_v1('course_url.max_retraction_pct', 5),
    'enabled', security.pipeline_num_v1('course_url.fill_enabled', 1) = 1)
  from f
$$;
comment on function security.course_url_retraction_30d_v1() is 'course_url fills in the last 30 days, how many were taken back and why (NZ brief item 5 guard 4); read by the fill job and the hourly report';

-- 4 the fill job ------------------------------------------------------------------------------------------------------------------
create or replace function security.course_url_fill_v1() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_batch int := greatest(100, least(security.pipeline_num_v1('batch.course_url_fill', 2000)::int, 5000));
        v_rate jsonb; v_retracted int := 0; v_emptied int := 0; v_filled int := 0; v_refilled int := 0; v_by jsonb; v_now timestamptz := clock_timestamp();
begin
  if security.pipeline_num_v1('course_url.fill_enabled', 1) <> 1 then
    return jsonb_build_object('skipped', 'course_url.fill_enabled is 0');
  end if;
  -- guard 4: pause when too many recent fills were taken back
  v_rate := security.course_url_retraction_30d_v1();
  if (v_rate->>'filled')::int >= 50 and coalesce((v_rate->>'retraction_pct')::numeric, 0) > security.pipeline_num_v1('course_url.max_retraction_pct', 5) then
    update pipeline.platform_toolset_settings set value = '0'::jsonb, reason = 'paused by the fill job: ' || (v_rate->>'retraction_pct') || '% of the last 30 days'' fills were taken back (limit ' || (v_rate->>'max_pct') || '%)', updated_at = now()
      where toolset_key = 'pipeline' and key = 'course_url.fill_enabled';
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('catalogue', 'course_url_fill_paused', 'course_url.fill_enabled', v_rate, null);
    return jsonb_build_object('paused', v_rate);
  end if;
  -- guard 3: take back fills whose binding changed (page no longer bound, or a different copy)
  with gone as (
    update pipeline.course_url_fills u
       set retracted_at = now(),
           retract_reason = case when p.course_id is null or p.status <> 'bound' then 'page no longer bound' else 'binding changed' end
      from pipeline.course_url_fills x
      left join pipeline.coverage_course_pages p on p.course_id = x.course_id
     where u.course_id = x.course_id and x.retracted_at is null
       and (p.course_id is null or p.status <> 'bound' or p.evidence_id is distinct from x.evidence_id)
    returning u.course_id, u.url)
  , emptied as (
    update catalogue.courses c set course_url = null, updated_at = now()
      from gone g
     where c.id = g.course_id and c.course_url = g.url
       and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field = 'course_url')
    returning c.id)
  select (select count(*) from gone), (select count(*) from emptied) into v_retracted, v_emptied;
  -- guards 1 and 2: fill empty links from proven bindings, in the countries allowed, never a locked course
  with f as (
    select c.id course_id, coalesce(nullif(p.candidates->>'final_url', ''), p.url) url, p.evidence_id, p.identity_basis, k.iso_alpha2 cc
      from catalogue.courses c
      join catalogue.providers pr on pr.id = c.provider_id
      join ref.countries k on k.id = pr.country_id
      join pipeline.coverage_course_pages p on p.course_id = c.id
     where c.lifecycle_status = 'active' and c.course_url is null
       and p.status = 'bound' and p.identity_basis is not null and p.read_status = 'read' and p.evidence_id is not null
       and coalesce(nullif(p.candidates->>'final_url', ''), p.url) ~* '^https?://'
       and k.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'course_url.fill_countries')
       and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field = 'course_url')
       and not exists (select 1 from pipeline.course_url_fills x where x.course_id = c.id and x.retracted_at is null)
     order by (k.iso_alpha2 = 'NZ') desc, c.id
     limit v_batch),
  ins as (
    insert into pipeline.course_url_fills(course_id, url, evidence_id, identity_basis, filled_at, retracted_at, retract_reason)
    select course_id, url, evidence_id, identity_basis, v_now, null, null from f
    on conflict (course_id) do update set url = excluded.url, evidence_id = excluded.evidence_id, identity_basis = excluded.identity_basis, filled_at = v_now, retracted_at = null, retract_reason = null
    returning course_id, (xmax <> 0) again),
  upd as (
    update catalogue.courses c set course_url = f.url, updated_at = now() from f where c.id = f.course_id and c.course_url is null
    returning c.id)
  select (select count(*) from upd), (select count(*) from ins where again) into v_filled, v_refilled;
  select coalesce(jsonb_object_agg(cc, n), '{}'::jsonb) into v_by
    from (select k.iso_alpha2 cc, count(*) n from pipeline.course_url_fills x join catalogue.courses c on c.id = x.course_id join catalogue.providers pr on pr.id = c.provider_id join ref.countries k on k.id = pr.country_id
           where x.filled_at = v_now group by 1) z;
  if v_filled > 0 or v_retracted > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('catalogue', 'course_url_filled', 'courses.course_url',
            jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'batch', v_batch), null);
  end if;
  if v_filled > 0 or v_emptied > 0 then
    insert into search.refresh_requests(requested_by) values ('course_url fill (' || v_filled || ' filled, ' || v_emptied || ' emptied)');
  end if;
  return jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'rate', v_rate);
end $$;
comment on function security.course_url_fill_v1() is 'nightly: fills an empty course_url from the course''s proven own page (four guards: proven binding only, manual locks honoured, re-fill on binding change, pauses above the 30-day retraction limit); NZ brief item 5 Option A';

-- 5 job: catalogue row before the schedule -------------------------------------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('course-url-fill', 'Catalogue', 60, 'Official link: fill from the proven page',
  'Daily at 02:23 UTC: for courses with no official link in Official link: countries filled, writes the address of the course''s proven own page (bound, proof on the page, stored copy) into course_url; takes a link back when the page is no longer bound or its copy changed, and fills again from the new binding. Never touches a locked or person-set link. Pauses itself when more than Official link: most taken back of the last 30 days'' fills were taken back. Handles Official link: links filled a run courses a run.',
  6, true, null)
on conflict (jobname) do nothing;
select cron.schedule('course-url-fill', '23 2 * * *', $$select security.course_url_fill_v1()$$);

-- 6 register ----------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.course_url_fills', 'Catalogue', 'course_url values filled from proven bindings, with retractions (NZ brief item 5)', 'active', '{}', '20261024001000'),
 ('function', 'security.course_url_fill_v1', 'Catalogue', 'nightly course_url fill with the four guards', 'active', '{}', '20261024001000'),
 ('function', 'security.course_url_retraction_30d_v1', 'Catalogue', '30-day retraction figure for the fill (guard 4; hourly report)', 'active', '{}', '20261024001000'),
 ('job', 'course-url-fill', 'Catalogue', 'daily 02:23 UTC course_url fill', 'active', '{}', '20261024001000')
on conflict (kind, name) do nothing;

do $t$ declare r jsonb; s jsonb; w jsonb; g jsonb; begin
  select jsonb_object_agg(cc, n) into w from (select k.iso_alpha2 cc, count(*) n from catalogue.courses c join catalogue.providers pr on pr.id=c.provider_id join ref.countries k on k.id=pr.country_id join pipeline.coverage_course_pages p on p.course_id=c.id where c.lifecycle_status='active' and c.course_url is null and p.status='bound' and p.identity_basis is not null and p.read_status='read' and p.evidence_id is not null and coalesce(nullif(p.candidates->>'final_url',''),p.url) ~* '^https?://' and not exists (select 1 from pipeline.manual_locks m where m.entity='course' and m.entity_id=c.id and m.field='course_url') group by 1) z;
  update pipeline.platform_toolset_settings set value='5000'::jsonb where toolset_key='pipeline' and key='batch.course_url_fill';
  r := security.course_url_fill_v1();
  select jsonb_agg(jsonb_build_object('c', left(c.canonical_title,40), 'p', left(pr.canonical_name,24), 'b', x.identity_basis, 'u', left(x.url,70))) into s
    from (select * from pipeline.course_url_fills order by random() limit 10) x join catalogue.courses c on c.id=x.course_id join catalogue.providers pr on pr.id=c.provider_id;
  update pipeline.coverage_course_pages set status='mismatch' where course_id = (select course_id from pipeline.course_url_fills limit 1);
  g := security.course_url_fill_v1();
  raise exception 'DRYRUN OK %', jsonb_build_object('all_countries', w, 'basis_mix', (select jsonb_object_agg(identity_basis, n) from (select identity_basis, count(*) n from pipeline.course_url_fills group by 1) z), 'samples', s, 'second_run', g - 'rate', 'nz_url_after', (select count(*) from catalogue.courses c join catalogue.providers pr on pr.id=c.provider_id join ref.countries k on k.id=pr.country_id where k.iso_alpha2='NZ' and c.lifecycle_status='active' and c.course_url is not null)); end $t$;
