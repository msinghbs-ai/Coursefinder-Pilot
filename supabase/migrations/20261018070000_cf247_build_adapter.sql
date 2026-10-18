-- CF-247 Decision 267 (18 Oct 2026): Build adapter, one click per university. Platform Admin 17 Oct 18:56 ("click and generate the adapter
-- and configure it for all fields available in the db and seek value for enrichment or foundation fill"); choices "One admin click
-- (Recommended)", fields "Duration, Campus, Majors / specialisations, Study level / AQF"; 18 Oct 11:58 "position and plan it on right ui";
-- 12:43 "proceed with Phase 2".
-- It reuses what already runs: onboarding builds the adapter (website, course pages, capture, AI proposal, apply, qualify); the adapter
-- admits intakes, fee, English and delivery; Enrichment fills duration, campus and study level where the catalogue has none.
-- New here:
-- 1 Readiness for eight fields per university (security.adapter_build_fields_v1): Ready (read on enough pages and agreeing with what the
--   catalogue holds), Review (read, but on too few pages or disagreeing), Not ready (not read). The shares are the existing qualify settings.
--   Duration, campus, study level and majors are measured the same way as the four adapter fields. Each field says what it would add.
-- 2 pipeline.adapter_builds: the latest readiness per university (job adapter-build-readiness keeps it current), its wave and what was
--   admitted from it.
-- 3 public.admin_adapter_build: list (universities with stage and readiness), read (one university, measured now), build (starts or retries
--   onboarding), admit (one click: only Ready fields; intakes, fee, English and delivery through the adapter, duration, campus and study
--   level through an Enrichment task for that university, majors written to the new catalogue.course_specialisations), set_wave, waves.
-- 4 Majors and specialisations become an adapter pattern field ('majors', worker v0.30.0) and have their own table, beside the catalogue.
--   The website API does not send them (Decision 266: a later, approved API change may).
-- Nothing the website or Zoho reads changes shape. Values admitted go into the same tables and columns as before.
-- Replaces: security.uni_adapter_pattern_fields (adds majors)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$ begin
  if md5(pg_get_functiondef('security.uni_adapter_pattern_fields'::regproc)) <> 'c51ffc49c0cbfd1590cf02061c44645e' then
    raise exception 'security.uni_adapter_pattern_fields is not the definition this change replaces';
  end if;
end $guard$;

CREATE OR REPLACE FUNCTION security.uni_adapter_pattern_fields()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array['intakes', 'fee', 'ielts_overall', 'campus', 'mode', 'duration', 'study_level', 'student_type', 'not_admitting', 'aqf_level', 'location', 'fee_total', 'course_years', 'exit_awards', 'entry_requirement', 'other_requirements', 'english_level', 'majors']
$function$;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.adapter_build_readiness', 'Universities measured per run (Build adapter)', 'Each run of the adapter-build-readiness job measures this many universities with an adapter, the longest unmeasured first.', 'number', '100', 10, 500, 'universities', 314, 'CF-247 Decision 267, 18 Oct 2026', 'Enrichment', 'job adapter-build-readiness'),
 ('pipeline', 'build.duration_tolerance_years', 'Duration agreement (Build adapter)', 'A duration read from the course page agrees with the catalogue when the two differ by no more than this many years (registers often count weeks).', 'number', '0.25', 0, 1, 'years', 315, 'CF-247 Decision 267, 18 Oct 2026', 'Enrichment', 'security.adapter_build_fields_v1')
on conflict (toolset_key, key) do nothing;

create table if not exists catalogue.course_specialisations (
  id bigint generated always as identity primary key,
  course_id uuid not null references catalogue.courses(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 200),
  source text not null default 'adapter',
  evidence_id uuid,
  page_url text,
  status text not null default 'active' check (status in ('active', 'withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists course_specialisations_course_name on catalogue.course_specialisations (course_id, lower(name));
comment on table catalogue.course_specialisations is 'CF-247 Decision 267: majors and specialisations a course page names, admitted from a Ready adapter field (one row per name). Not sent by the website API (Decision 266).';
alter table catalogue.course_specialisations enable row level security;
revoke all on table catalogue.course_specialisations from anon, authenticated;

create table if not exists pipeline.adapter_builds (
  provider_id uuid primary key references catalogue.providers(id) on delete cascade,
  readiness jsonb,
  pages_read int not null default 0,
  ready int not null default 0,
  review int not null default 0,
  not_ready int not null default 0,
  adds int not null default 0,
  checked_at timestamptz,
  wave text,
  admitted jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
comment on table pipeline.adapter_builds is 'CF-247 Decision 267: Build adapter, one row per university: the latest field readiness (job adapter-build-readiness), its wave and what one click admitted (latest only).';
alter table pipeline.adapter_builds enable row level security;
revoke all on table pipeline.adapter_builds from anon, authenticated;

-- readiness of the eight fields for one university
create or replace function security.adapter_build_fields_v1(p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_min_read numeric := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  v_min_agree numeric := coalesce((security.firecrawl_setting('qualify_agree_share') #>> '{}')::numeric, 0.9);
  v_tol numeric := security.pipeline_num_v1('build.duration_tolerance_years', 0.25);
  q jsonb; v_pages int; v_out jsonb := '{}'::jsonb; r record; v_share numeric; v_agree numeric; v_state text; v_why text;
  u pipeline.uni_adapters%rowtype; b pipeline.adapter_builds%rowtype; v_adds int := 0;
begin
  select * into u from pipeline.uni_adapters where provider_id = p_provider_id;
  select * into b from pipeline.adapter_builds where provider_id = p_provider_id;
  q := case when u.provider_id is not null then security.adapter_qualify_one_v1(p_provider_id, v_min_read, v_min_agree) end;
  v_pages := coalesce((q->>'pages_read')::int, (select count(*) from pipeline.coverage_course_pages pg where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null));
  for r in
    with pg as (
      select pg.course_id, pg.candidates->'adapter_extra' x, (c0.lifecycle_status = 'active') act from pipeline.coverage_course_pages pg
        join catalogue.courses c0 on c0.id = pg.course_id
       where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null),
    d as (
      select 'duration' field, count(*) filter (where y.rd) rd, count(*) filter (where y.rd and y.held and y.eq) ag, count(*) filter (where y.rd and y.held and not y.eq) df, count(*) filter (where y.rd and not y.held and y.act) nw
        from (select pg.act, pv is not null rd, c.duration_value is not null held,
                     abs(coalesce(security.adapter_build_years_v1((pv->>'value')::numeric, pv->>'unit'), -99) - coalesce(security.adapter_build_years_v1(c.duration_value, c.duration_unit), 99)) <= v_tol eq
                from pg join catalogue.courses c on c.id = pg.course_id
                cross join lateral (select security.enrich_parse_duration_v1(pg.x->>'duration') pv) z) y
      union all
      select 'study_level', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, lv.id is not null rd, c.study_level_id is not null held,
                     security.adapter_build_level_family_v1(lv.short_code) = security.adapter_build_level_family_v1(hl.short_code) eq
                from pg join catalogue.courses c on c.id = pg.course_id
                left join ref.study_levels lv on lv.id = security.enrich_parse_level_v1(coalesce(pg.x->>'study_level', pg.x->>'aqf_level'))
                left join ref.study_levels hl on hl.id = c.study_level_id) y
      union all
      select 'campus', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, v is not null rd,
                     exists (select 1 from catalogue.course_campuses cc where cc.course_id = pg.course_id) held,
                     exists (select 1 from catalogue.course_campuses cc join catalogue.campuses k on k.id = cc.campus_id
                              where cc.course_id = pg.course_id
                                and strpos(lower(v), lower(btrim(regexp_replace(k.name, '\s*campus\s*', ' ', 'gi')))) > 0) eq
                from pg cross join lateral (select nullif(btrim(coalesce(pg.x->>'campus', pg.x->>'location')), '') v) z) y
      union all
      select 'majors', count(*) filter (where y.rd), count(*) filter (where y.rd and y.held and y.eq), count(*) filter (where y.rd and y.held and not y.eq), count(*) filter (where y.rd and not y.held and y.act)
        from (select pg.act, v is not null rd,
                     exists (select 1 from catalogue.course_specialisations s where s.course_id = pg.course_id and s.status = 'active') held,
                     (select coalesce(array_agg(lower(s.name) order by lower(s.name)), '{}') from catalogue.course_specialisations s where s.course_id = pg.course_id and s.status = 'active')
                       = security.adapter_build_majors_v1(v) eq
                from pg cross join lateral (select nullif(btrim(pg.x->>'majors'), '') v) z) y)
    select * from d
  loop
    v_share := case when v_pages > 0 then round(r.rd::numeric / v_pages, 3) else 0 end;
    v_agree := case when (r.ag + r.df) > 0 then round(r.ag::numeric / (r.ag + r.df), 3) end;
    v_out := v_out || jsonb_build_object(r.field, jsonb_build_object('read', r.rd, 'agree', r.ag, 'differ', r.df, 'new', r.nw, 'read_share', v_share, 'agree_share', v_agree));
  end loop;
  -- the four adapter fields as qualification measures them
  for r in select k, v from jsonb_each(coalesce(q->'fields', '{}'::jsonb)) x(k, v) where k in ('intakes', 'fee', 'english', 'delivery') loop
    v_out := v_out || jsonb_build_object(r.k, jsonb_build_object('read', (r.v->>'read')::int, 'agree', (r.v->>'agree')::int, 'differ', (r.v->>'differ')::int, 'new', (r.v->>'new')::int,
                                         'read_share', (r.v->>'read_share')::numeric, 'agree_share', (r.v->>'agree_share')::numeric, 'unclear', (r.v->>'unclear')::int));
  end loop;
  for r in select f, ord from unnest(array['intakes', 'fee', 'english', 'delivery', 'duration', 'campus', 'study_level', 'majors']) with ordinality t(f, ord) loop
    if not v_out ? r.f then v_out := v_out || jsonb_build_object(r.f, jsonb_build_object('read', 0, 'agree', 0, 'differ', 0, 'new', 0, 'read_share', 0, 'agree_share', null)); end if;
    v_share := (v_out->r.f->>'read_share')::numeric; v_agree := (v_out->r.f->>'agree_share')::numeric;
    if (v_out->r.f->>'read')::int = 0 then v_state := 'not_ready';
      v_why := case when u.provider_id is null then 'no adapter yet' when r.f = 'majors' and not (coalesce(u.patterns, '{}'::jsonb) ? 'majors') then 'the adapter does not read majors yet' else 'not read by the adapter' end;
    elsif v_share < v_min_read then v_state := 'review'; v_why := format('read on %s of %s pages, under the %s%% needed', v_out->r.f->>'read', v_pages, round(v_min_read * 100));
    elsif v_agree is not null and v_agree < v_min_agree then v_state := 'review'; v_why := format('%s of %s readings differ from the catalogue', v_out->r.f->>'differ', (v_out->r.f->>'agree')::int + (v_out->r.f->>'differ')::int);
    else v_state := 'ready'; v_why := case when (v_out->r.f->>'new')::int > 0 then format('adds %s values the catalogue does not hold', v_out->r.f->>'new') else 'agrees with the catalogue' end; end if;
    v_out := jsonb_set(v_out, array[r.f], (v_out->r.f) || jsonb_build_object('state', v_state, 'why', v_why, 'order', r.ord,
              'admitted', case when r.f in ('intakes', 'fee', 'english', 'delivery') then coalesce(u.admit, false) and r.f = any (coalesce(u.admit_fields, '{}'))
                               else coalesce(b.admitted, '{}'::jsonb) ? r.f end));
    if v_state = 'ready' then v_adds := v_adds + (v_out->r.f->>'new')::int; end if;
  end loop;
  return jsonb_build_object('provider_id', p_provider_id, 'pages_read', v_pages, 'has_adapter', u.provider_id is not null, 'fields', v_out,
    'ready', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'ready'),
    'review', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'review'),
    'not_ready', (select coalesce(jsonb_agg(k order by (v->>'order')::int), '[]'::jsonb) from jsonb_each(v_out) x(k, v) where v->>'state' = 'not_ready'),
    'adds', v_adds, 'min_read', v_min_read, 'min_agree', v_min_agree, 'measured_at', now());
end $function$;

create or replace function security.adapter_build_years_v1(p_value numeric, p_unit text)
returns numeric language sql immutable set search_path = '' as $function$
  select case lower(coalesce(p_unit, '')) when 'years' then p_value when 'months' then p_value / 12 when 'weeks' then p_value / 52  -- fixed: calendar units
                                         when 'semesters' then p_value / 2 end
$function$;

create or replace function security.adapter_build_level_family_v1(p_code text)
returns text language sql immutable set search_path = '' as $function$
  select case when p_code in ('MA', 'MC', 'MR', 'ME') then 'M' when p_code in ('CT', 'C1', 'C2', 'C3', 'C4') then 'C' else p_code end
$function$;

create or replace function security.adapter_build_majors_v1(p_text text)
returns text[] language sql immutable set search_path = '' as $function$
  select coalesce(array_agg(distinct lower(btrim(m)) order by lower(btrim(m))), '{}')
    from regexp_split_to_table(coalesce(p_text, ''), '\s*(\||;|\n)\s*') m where length(btrim(m)) between 2 and 200
$function$;

create or replace function security.adapter_build_store_v1(p_provider_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare r jsonb := security.adapter_build_fields_v1(p_provider_id);
begin
  insert into pipeline.adapter_builds(provider_id, readiness, pages_read, ready, review, not_ready, adds, checked_at, updated_at)
  values (p_provider_id, r, (r->>'pages_read')::int, jsonb_array_length(r->'ready'), jsonb_array_length(r->'review'), jsonb_array_length(r->'not_ready'), (r->>'adds')::int, now(), now())
  on conflict (provider_id) do update set readiness = excluded.readiness, pages_read = excluded.pages_read, ready = excluded.ready, review = excluded.review,
         not_ready = excluded.not_ready, adds = excluded.adds, checked_at = now(), updated_at = now();
  return r;
end $function$;

create or replace function security.adapter_build_refresh_v1()
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_n int := 0; p uuid;
begin
  for p in select u.provider_id from pipeline.uni_adapters u left join pipeline.adapter_builds b on b.provider_id = u.provider_id
            where u.enabled order by b.checked_at nulls first, u.provider_id
            limit security.pipeline_num_v1('batch.adapter_build_readiness', 100)::int loop
    perform security.adapter_build_store_v1(p); v_n := v_n + 1;
  end loop;
  return jsonb_build_object('measured', v_n);
end $function$;

-- majors: the latest Ready reading per course, one row per name
create or replace function security.adapter_build_admit_majors_v1(p_provider_id uuid)
returns int language plpgsql security definer set search_path = '' as $function$
declare v_n int;
begin
  insert into catalogue.course_specialisations(course_id, name, source, evidence_id, page_url)
  select pg.course_id, initcap(m), 'adapter', pg.evidence_id, pg.url
    from pipeline.coverage_course_pages pg
    cross join lateral unnest(security.adapter_build_majors_v1(pg.candidates->'adapter_extra'->>'majors')) m
   where pg.provider_id = p_provider_id and pg.read_status = 'read' and pg.identity_basis is not null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = pg.course_id and l.field = 'majors')
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

create or replace function public.admin_adapter_build(p_action text, p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', ''));
  v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_pids uuid[]; v_cc text := upper(nullif(btrim(p_args->>'country'), ''));
  v_q text := nullif(btrim(p_args->>'query'), ''); v_stage text := nullif(btrim(p_args->>'stage'), ''); v_wave text := nullif(btrim(p_args->>'wave'), '');
  v_limit int := least(greatest(coalesce((p_args->>'limit')::int, 50), 1), 200);  -- fixed: page size bounds
  v_offset int := greatest(coalesce((p_args->>'offset')::int, 0), 0);
  r jsonb; v_fields text[]; v_adapter text[]; v_enrich text[]; v_done jsonb := '[]'::jsonb; v_job jsonb; v_m int; v_open uuid[]; v_stopped uuid[]; v_new uuid[]; p uuid; v_item jsonb;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  v_pids := coalesce(array(select x::uuid from jsonb_array_elements_text(coalesce(p_args->'provider_ids', '[]'::jsonb)) x), '{}');
  if v_pid is not null then v_pids := array_append(v_pids, v_pid); end if;

  if p_action in ('list', 'waves') then
    return (with base as (
      select pr.id provider_id, coalesce(pr.display_name, pr.canonical_name) name, k.iso_alpha2::text country,
             (select count(*) from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active') courses,
             b.pages_read, b.ready, b.review, b.not_ready, b.adds, b.checked_at, b.wave, b.readiness->'ready' ready_fields,
             u.enabled adapter_on, coalesce(u.admit, false) and cardinality(coalesce(u.admit_fields, '{}')) > 0 admitting,
             o.status onboarding, o.stop_reason, o.note onboarding_note,
             case when o.status is not null and o.status not in ('done', 'cancelled', 'stopped') then 'building'
                  when coalesce(u.admit, false) and cardinality(coalesce(u.admit_fields, '{}')) > 0 then 'admitted'
                  when u.enabled then 'tested'
                  when o.status = 'stopped' and o.stop_reason in ('too_few_pages', 'no_website') then 'needs_pages'
                  when o.status = 'stopped' then 'stopped'
                  else 'no_adapter' end stage
        from catalogue.providers pr
        join ref.countries k on k.id = pr.country_id
        left join pipeline.uni_adapters u on u.provider_id = pr.id
        left join pipeline.adapter_builds b on b.provider_id = pr.id
        left join lateral (select * from pipeline.provider_onboarding o where o.provider_id = pr.id order by o.created_at desc limit 1) o on true
       where coalesce(pr.lifecycle_status, 'active') = 'active'
         and k.iso_alpha2::text = any (security.catalogue_country_codes_v1())
         and exists (select 1 from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active')
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pr.id)
         and (v_cc is null or k.iso_alpha2::text = v_cc)
         and (v_q is null or pr.canonical_name ilike '%' || v_q || '%' or coalesce(pr.display_name, '') ilike '%' || v_q || '%')
         and (v_wave is null or b.wave = v_wave)),
      f as (select * from base where v_stage is null or stage = v_stage)
      select case when p_action = 'waves' then
        jsonb_build_object('waves', coalesce((select jsonb_agg(jsonb_build_object('wave', w.wave, 'universities', w.n, 'courses', w.courses, 'by_stage', w.by_stage, 'ready', w.ready, 'review', w.review, 'not_ready', w.not_ready, 'adds', w.adds) order by w.wave)
                    from (select wave, count(*) n, sum(courses) courses, sum(ready) ready, sum(review) review, sum(not_ready) not_ready, sum(adds) adds,
                                 (select jsonb_object_agg(s.stage, s.n) from (select stage, count(*) n from base b2 where b2.wave = b1.wave group by stage) s) by_stage
                            from base b1 where wave is not null group by wave) w), '[]'::jsonb))
      else jsonb_build_object(
        'summary', (select jsonb_build_object('universities', count(*), 'courses', sum(courses), 'by_stage', (select jsonb_object_agg(s.stage, s.n) from (select stage, count(*) n from base group by stage) s),
                                              'ready', sum(ready), 'review', sum(review), 'not_ready', sum(not_ready), 'adds', sum(adds)) from base),
        'total', (select count(*) from f), 'limit', v_limit, 'offset', v_offset,
        'items', coalesce((select jsonb_agg(to_jsonb(z))
                             from (select * from f order by case stage when 'tested' then 1 when 'building' then 2 when 'needs_pages' then 3 when 'stopped' then 4 when 'no_adapter' then 5 else 6 end,
                                                          adds desc nulls last, courses desc, name limit v_limit offset v_offset) z), '[]'::jsonb),
        'can_build', v_rank >= 5, 'can_admit', v_rank >= 6) end
      from (select 1) one);

  elsif p_action = 'read' then
    if v_pid is null then raise exception 'choose a university'; end if;
    r := case when v_rank >= 5 then security.adapter_build_store_v1(v_pid) else security.adapter_build_fields_v1(v_pid) end;
    return r || jsonb_build_object(
      'university', (select jsonb_build_object('name', coalesce(pr.display_name, pr.canonical_name), 'website', pr.website, 'country', k.iso_alpha2) from catalogue.providers pr join ref.countries k on k.id = pr.country_id where pr.id = v_pid),
      'courses', (select count(*) from catalogue.courses c where c.provider_id = v_pid and c.lifecycle_status = 'active'),
      'pages', (select jsonb_build_object('bound', count(*), 'read', count(*) filter (where read_status = 'read' and identity_basis is not null),
                                          'other_course', count(*) filter (where read_status = 'identity_mismatch'), 'unreadable', count(*) filter (where read_status in ('fetch_failed', 'blocked', 'refused_host', 'robots_disallowed', 'needs_render', 'too_thin')))
                  from pipeline.coverage_course_pages where provider_id = v_pid),
      'links_fixed', (select count(*) from pipeline.admin_control_events e where e.action = 'rebind' and e.area = 'coverage'
                         and (e.detail->>'course_id')::uuid in (select c.id from catalogue.courses c where c.provider_id = v_pid)),
      'adapter', (select jsonb_build_object('enabled', u.enabled, 'admit', u.admit, 'admit_fields', u.admit_fields, 'updated_at', u.updated_at, 'patterns', (select jsonb_agg(k) from jsonb_object_keys(coalesce(u.patterns, '{}'::jsonb)) k)) from pipeline.uni_adapters u where u.provider_id = v_pid),
      'build', (select jsonb_build_object('status', o.status, 'stage', security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result), 'stop_reason', o.stop_reason, 'note', o.note,
                                          'started_at', o.started_at, 'finished_at', o.finished_at, 'updated_at', o.updated_at)
                  from pipeline.provider_onboarding o where o.provider_id = v_pid order by o.created_at desc limit 1),
      'ai_cost_usd', (select round(coalesce(sum(d.cost_usd), 0), 3) from pipeline.uni_adapter_drafts d where d.provider_id = v_pid),
      'wave', (select wave from pipeline.adapter_builds where provider_id = v_pid),
      'admitted', (select admitted from pipeline.adapter_builds where provider_id = v_pid),
      'can_build', v_rank >= 5, 'can_admit', v_rank >= 6);

  elsif p_action = 'build' then
    if v_rank < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept with the build)'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    v_open := array(select distinct o.provider_id from pipeline.provider_onboarding o where o.provider_id = any (v_pids) and o.status not in ('done', 'cancelled', 'stopped'));
    v_stopped := array(select o.id from (select distinct on (o.provider_id) o.* from pipeline.provider_onboarding o where o.provider_id = any (v_pids) order by o.provider_id, o.created_at desc) o
                        where o.status = 'stopped');
    v_new := array(select i from unnest(v_pids) i where i <> all (v_open)
                     and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = i and o.status = 'stopped'
                                       and o.created_at = (select max(o2.created_at) from pipeline.provider_onboarding o2 where o2.provider_id = i)));
    if cardinality(v_stopped) > 0 then perform public.admin_provider_onboarding('retry', jsonb_build_object('ids', to_jsonb(v_stopped), 'reason', 'Build adapter: ' || v_reason)); end if;
    if cardinality(v_new) > 0 then perform public.admin_provider_onboarding('start', jsonb_build_object('provider_ids', to_jsonb(v_new), 'reason', 'Build adapter: ' || v_reason)); end if;
    if v_wave is not null then
      insert into pipeline.adapter_builds(provider_id, wave) select i, v_wave from unnest(v_pids) i
      on conflict (provider_id) do update set wave = excluded.wave, updated_at = now();
    end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('adapters', 'build', cardinality(v_pids) || ' universities', jsonb_build_object('decision', 267, 'reason', v_reason, 'wave', v_wave, 'started', cardinality(v_new), 'retried', cardinality(v_stopped), 'already_building', cardinality(v_open), 'provider_ids', to_jsonb(v_pids)), auth.uid());
    return jsonb_build_object('started', cardinality(v_new), 'retried', cardinality(v_stopped), 'already_building', cardinality(v_open));

  elsif p_action = 'set_wave' then
    if v_rank < 5 then raise exception 'PIM Operator or Platform Admin required' using errcode = '42501'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    insert into pipeline.adapter_builds(provider_id, wave) select i, v_wave from unnest(v_pids) i
    on conflict (provider_id) do update set wave = excluded.wave, updated_at = now();
    return jsonb_build_object('ok', true, 'wave', v_wave, 'universities', cardinality(v_pids));

  elsif p_action = 'admit' then
    if v_rank < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
    if cardinality(v_pids) = 0 then raise exception 'choose universities'; end if;
    v_fields := case when p_args ? 'fields' then array(select jsonb_array_elements_text(p_args->'fields')) end;
    foreach p in array v_pids loop
      r := security.adapter_build_store_v1(p);
      -- only Ready fields are admitted, whatever was asked
      v_adapter := array(select f from jsonb_array_elements_text(r->'ready') f where f in ('intakes', 'fee', 'english', 'delivery') and (v_fields is null or f = any (v_fields)) and not (r->'fields'->f->>'admitted')::boolean);
      -- duration, campus and study level fill only what the catalogue lacks, so they run whenever a Ready field has values to add
      v_enrich := array(select f from jsonb_array_elements_text(r->'ready') f where f in ('duration', 'campus', 'study_level') and (v_fields is null or f = any (v_fields)) and (r->'fields'->f->>'new')::int > 0);
      v_m := null; v_job := null;
      if cardinality(v_adapter) > 0 then
        perform public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', p, 'admit', true, 'reason', 'Build adapter: ' || v_reason,
                  'fields', to_jsonb(array(select distinct f from unnest(coalesce((select u.admit_fields from pipeline.uni_adapters u where u.provider_id = p and u.admit), '{}') || v_adapter) f order by f))));
      end if;
      if cardinality(v_enrich) > 0 then
        v_job := public.admin_enrich_fields('start', jsonb_build_object('provider_ids', jsonb_build_array(p), 'reason', 'Build adapter: ' || v_reason,
                  'fields', to_jsonb(array(select case f when 'study_level' then 'level' else f end from unnest(v_enrich) f))));
      end if;
      if 'majors' in (select jsonb_array_elements_text(r->'ready')) and (v_fields is null or 'majors' = any (v_fields)) and (r->'fields'->'majors'->>'new')::int > 0 then
        v_m := security.adapter_build_admit_majors_v1(p);
      end if;
      v_item := jsonb_build_object('provider_id', p, 'adapter_fields', to_jsonb(v_adapter), 'enrich_fields', to_jsonb(v_enrich), 'enrich_job', v_job->'job_id', 'majors_written', v_m,
                              'left_for_review', r->'review', 'not_ready', r->'not_ready');
      update pipeline.adapter_builds set admitted = admitted
               || coalesce((select jsonb_object_agg(f, jsonb_build_object('at', now(), 'by', auth.uid(), 'job_id', v_job->'job_id')) from unnest(v_enrich) f), '{}'::jsonb)
               || case when v_m is not null then jsonb_build_object('majors', jsonb_build_object('at', now(), 'by', auth.uid(), 'written', v_m)) else '{}'::jsonb end,
             updated_at = now()
       where provider_id = p;
      v_done := v_done || v_item;
    end loop;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('adapters', 'build_admit', cardinality(v_pids) || ' universities', jsonb_build_object('decision', 267, 'reason', v_reason, 'fields_asked', to_jsonb(v_fields), 'done', v_done), auth.uid());
    return jsonb_build_object('admitted', v_done);
  end if;
  raise exception 'unknown action %', p_action using errcode = '22023';
end $function$;

revoke execute on function security.adapter_build_fields_v1(uuid), security.adapter_build_store_v1(uuid), security.adapter_build_refresh_v1(), security.adapter_build_admit_majors_v1(uuid) from public, anon, authenticated;
revoke execute on function public.admin_adapter_build(text, jsonb) from public, anon;
grant execute on function public.admin_adapter_build(text, jsonb) to authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('adapter-build-readiness', 'Course pages', 46, 'Build adapter readiness', 'Hourly: measures, for universities with an adapter, which of eight fields are Ready, for Review or Not ready, and what each would add (Decision 267).', 4, true)
on conflict (jobname) do nothing;
select cron.schedule('adapter-build-readiness', '17 * * * *', $$select security.adapter_build_refresh_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('table', 'pipeline.adapter_builds', 'L2 read', 'Build adapter: field readiness, wave and what was admitted per university', 'active', '20261018070000'),
 ('table', 'catalogue.course_specialisations', 'Catalogue', 'Majors and specialisations admitted from course pages', 'active', '20261018070000'),
 ('job', 'adapter-build-readiness', 'L2 read', 'Measures Build adapter readiness hourly', 'active', '20261018070000'),
 ('function', 'public.admin_adapter_build', 'L2 read', 'Build adapter: list, read, build, admit, waves', 'active', '20261018070000'),
 ('function', 'security.adapter_build_fields_v1', 'L2 read', 'Readiness of eight fields for one university', 'active', '20261018070000'),
 ('function', 'security.adapter_build_admit_majors_v1', 'L2 read', 'Writes majors from Ready readings', 'active', '20261018070000')
on conflict (kind, name) do nothing;

-- first measurement for every university with an adapter
do $first$ declare p uuid; begin
  for p in select provider_id from pipeline.uni_adapters where enabled loop perform security.adapter_build_store_v1(p); end loop;
end $first$;

do $post$
declare v_n int; v_drift jsonb;
begin
  select count(*) into v_n from pipeline.adapter_builds where readiness is not null;
  if v_n < (select count(*) from pipeline.uni_adapters where enabled) then raise exception 'Decision 267 post-check: readiness for % universities only', v_n; end if;
  if exists (select 1 from pipeline.adapter_builds where jsonb_array_length(readiness->'ready') + jsonb_array_length(readiness->'review') + jsonb_array_length(readiness->'not_ready') <> 8) then
    raise exception 'Decision 267 post-check: every university has eight fields';
  end if;
  v_drift := security.consumer_api_check_v1()->'drift';
  if jsonb_array_length(v_drift) > 0 then raise exception 'Decision 267 post-check: consumer API drift %', v_drift; end if;
end $post$;
