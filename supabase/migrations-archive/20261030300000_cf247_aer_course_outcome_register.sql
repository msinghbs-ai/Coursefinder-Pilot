-- CF-247 AER production closure, decision C1 (Platform Admin mandate 30 Oct 2026, admin docs/platform/nz-enrichment-brief/
-- 2026-10-30-aer-production-closure-mandate.md §4; decision lodged before code in 2026-10-30-aer-production-closure-response.md §0 C1):
-- the course outcome register. Every active course of the entry-read countries (setting entry.course_read_countries) gets one primary,
-- operator-exportable outcome for academic entry requirements:
--   admitted_course            the course has an active course-level row
--   admitted_provider          the provider has active provider-table rows (the resolver answers from its band table or minimum)
--   awaiting_review            the course's own read waits in Layer 4, or (after a finished course read) its provider's table does
--   no_requirement_published   the course's read finished and kept nothing (the reader's reason is kept)
--   no_course_url              no official course page was found
--   identity_unresolved        the page is a mismatch or ambiguous, or its identity basis is not accepted for entry requirements
--   source_unreadable          the read was held or failed, or the bound page has no stored copy
--   excluded                   the provider is outside the entry-read scope, or the course is eligible and its read is deferred
-- Why derived and cached (measured 30 Oct 2026 22:35 AEDT): the classification reads 31,854 courses with their pages, stored copies and the
-- identity rule (3.6 s for the identity part alone), close to the 8 s limit of a signed-in read. Job aer-outcome-register rebuilds it when it is
-- older than aer.outcome_register_every_minutes; public.admin_aer_outcomes answers from it with its build time and age.
-- Read only: nothing is admitted, read, queued, decided or changed in any source table. Never read by the consumer API (Decision 266).
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped, deleted or renamed by this migration (the job's rebuild clears and refills its own derived table inside its function).

-- 1. settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.outcome_register_every_minutes', 'AER course outcome register: rebuilt every',
  'The course outcome register (Catalogue › Entry requirements › Resolution inspection) is rebuilt this often. Each build reads every active course of the entry-read countries, about 15 seconds (13 s measured on 30 Oct 2026).', 'number',
  to_jsonb(60), 15, 1440, 'minutes', 792, 'Platform upkeep', 'job aer-outcome-register; public.admin_aer_outcomes',
  'CF-247 AER production closure C1 (Platform Admin mandate 30 Oct 2026 §4): one operator-exportable outcome per course'),
 ('pipeline', 'aer.outcome_register_page_rows', 'AER course outcome register: rows per download page',
  'Download CSV fetches the register in pages of this many rows (the whole register is downloaded; this only sets the size of each request).', 'number',
  to_jsonb(5000), 500, 10000, 'rows', 793, 'Platform upkeep', 'public.admin_aer_outcomes (rows)',
  'CF-247 AER production closure C1: keeps each download request well inside the 8 s read limit'),
 ('pipeline', 'aer.outcome_register_stale_after_minutes', 'AER course outcome register: marked stale after',
  'The register shows when it was built and how long ago; older than this it is marked Stale. Keep it above the rebuild interval.', 'number',
  to_jsonb(180), 30, 2880, 'minutes', 794, 'Platform upkeep', 'public.admin_aer_outcomes (build)',
  'CF-247 AER production closure C1: show the register''s build time and staleness')
on conflict (toolset_key, key) do nothing;

-- 2. tables
create table if not exists pipeline.aer_course_outcomes (
  course_id uuid primary key,
  provider_id uuid not null,
  country text not null,
  provider_name text,
  provider_published boolean not null,
  course_title text,
  course_code text,
  outcome text not null check (outcome in ('admitted_course', 'admitted_provider', 'awaiting_review', 'no_requirement_published',
                                            'no_course_url', 'identity_unresolved', 'source_unreadable', 'excluded')),
  detail text not null,
  course_url text,
  page_status text,
  identity_basis text,
  read_state text,
  read_reason text,
  review_item_id uuid,
  built_at timestamptz not null
);
create index if not exists aer_course_outcomes_order_idx on pipeline.aer_course_outcomes (country, provider_name, course_title, course_id);
comment on table pipeline.aer_course_outcomes is 'CF-247 AER production closure C1 (Platform Admin mandate 30 Oct 2026 §4): derived, read-only course outcome register for academic entry requirements, one primary outcome per active course of the entry-read countries; rebuilt by job aer-outcome-register (security.aer_course_outcomes_build_v1). Never read by the consumer API.';
alter table pipeline.aer_course_outcomes enable row level security;
revoke all on pipeline.aer_course_outcomes from public, anon, authenticated;

create table if not exists pipeline.aer_course_outcome_builds (
  built_at timestamptz primary key,
  finished_at timestamptz not null,
  took_ms integer not null,
  courses integer not null,
  by_outcome jsonb not null,
  source text not null check (source in ('job', 'migration'))
);
comment on table pipeline.aer_course_outcome_builds is 'CF-247 AER production closure C1: each build of the course outcome register with its count by outcome (the history of consumer coverage for entry requirements).';
alter table pipeline.aer_course_outcome_builds enable row level security;
revoke all on pipeline.aer_course_outcome_builds from public, anon, authenticated;

-- 3. the build (single flight) and the job's due check
create or replace function security.aer_course_outcomes_build_v1(p_source text default 'job')
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_t timestamptz := clock_timestamp(); v_n int; v_by jsonb;
begin
  -- single flight: an overlapping run does not build a second time
  if not pg_try_advisory_xact_lock(hashtextextended('cf247.aer.outcome_register', 0)) then return jsonb_build_object('state', 'busy'); end if;
  delete from pipeline.aer_course_outcomes;
  insert into pipeline.aer_course_outcomes(course_id, provider_id, country, provider_name, provider_published, course_title, course_code, outcome, detail,
                                           course_url, page_status, identity_basis, read_state, read_reason, review_item_id, built_at)
  with scope as (select (e.v)::uuid pid from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.course_read_providers'), '[]'::jsonb)) e(v)),
  c as (
    select c.id, c.provider_id, k.iso_alpha2 cc, coalesce(p.display_name, p.canonical_name) pname, p.publication_status = 'published' pub,
           coalesce(c.display_title, c.canonical_title) title, c.course_code, g.status gs, g.url, g.identity_basis,
           (e.storage_path is not null) stored,
           (g.status = 'bound' and security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')) id_ok,
           exists (select 1 from scope s where s.pid = c.provider_id) in_scope
      from catalogue.courses c
      join catalogue.providers p on p.id = c.provider_id
      join ref.countries k on k.id = p.country_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.evidence_artifacts e on e.id = g.evidence_id
     where c.lifecycle_status = 'active'
       and coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb) ? k.iso_alpha2),
  li as (select distinct on (f.course_id) f.course_id, f.state, f.reason from pipeline.field_enrich_items f
          where f.field = 'entry_requirements' order by f.course_id, f.updated_at desc),
  cpend as (select distinct on (i.entity_id) i.entity_id course_id, i.id from pipeline.layer4_review_items i
             where i.status = 'pending' and i.field_code = 'course_entry_first_read' order by i.entity_id, i.created_at),
  ppend as (select i.entity_id provider_id, count(*) n, (array_agg(i.id order by i.created_at))[1] first_id from pipeline.layer4_review_items i
             where i.status = 'pending' and i.field_code in ('entry_matrix_first_run', 'entry_matrix_change') group by i.entity_id),
  mact as (select m.provider_id, count(*) n from catalogue.provider_entry_matrix m where m.status = 'active' group by 1),
  cact as (select r.course_id, count(*) n from catalogue.course_entry_requirements r where r.status = 'active' group by 1)
  select c.id, c.provider_id, c.cc, c.pname, coalesce(c.pub, false), c.title, c.course_code, o.outcome, o.detail,
         c.url, c.gs, c.identity_basis, li.state, li.reason,
         case when o.outcome = 'awaiting_review' then coalesce(cp.id, pp.first_id) when cp.id is not null then cp.id end, now()
    from c
    left join li on li.course_id = c.id
    left join cpend cp on cp.course_id = c.id
    left join ppend pp on pp.provider_id = c.provider_id
    left join mact ma on ma.provider_id = c.provider_id
    left join cact ca on ca.course_id = c.id
    cross join lateral (select case
        when ca.n is not null then 'admitted_course'
        when ma.n is not null then 'admitted_provider'
        when cp.id is not null then 'awaiting_review'
        when li.state = 'skipped' then 'no_requirement_published'
        when pp.n is not null then 'awaiting_review'
        when c.gs is null then 'no_course_url'
        when c.gs <> 'bound' or not c.id_ok then 'identity_unresolved'
        when li.state = 'failed' or not c.stored then 'source_unreadable'
        else 'excluded' end outcome) oc
    cross join lateral (select oc.outcome, case oc.outcome
        when 'admitted_course' then ca.n || ' active course-level row(s)'
        when 'admitted_provider' then 'provider table active (' || ma.n || ' rows): the resolver answers by country'
             || case when cp.id is not null then '; the course''s own read also waits in Layer 4' else '' end
        when 'awaiting_review' then case when cp.id is not null then 'the course''s read waits in Layer 4 (course entry first read)'
             else 'the provider''s table waits in Layer 4 (' || pp.n || ' item(s))' end
        when 'no_requirement_published' then 'read finished, nothing kept: ' || coalesce(li.reason, 'no reason recorded')
             || case when pp.n is not null then '; the provider''s table waits in Layer 4' else '' end
        when 'no_course_url' then 'no official course page found'
        when 'identity_unresolved' then case when c.gs <> 'bound' then 'course page ' || c.gs
             else 'identity basis ' || coalesce(c.identity_basis, 'none') || ' is not accepted for entry requirements' end
        when 'source_unreadable' then case when li.state = 'failed' then 'read held or failed: ' || coalesce(li.reason, 'no reason recorded')
             else 'the bound course page has no stored copy' end
        else case when not c.in_scope then 'provider outside the entry-read scope (setting entry.course_read_providers)'
             else 'eligible, not read: course reads are held (AER production-closure mandate, 30 Oct 2026)' end end detail) o;
  get diagnostics v_n = row_count;
  select coalesce(jsonb_object_agg(x.outcome, x.n), '{}'::jsonb) into v_by from (select a.outcome, count(*) n from pipeline.aer_course_outcomes a group by 1) x;
  insert into pipeline.aer_course_outcome_builds(built_at, finished_at, took_ms, courses, by_outcome, source)
  values (v_t, clock_timestamp(), round(extract(epoch from clock_timestamp() - v_t) * 1000)::int, v_n, v_by, p_source);
  return jsonb_build_object('state', 'built', 'courses', v_n, 'took_ms', round(extract(epoch from clock_timestamp() - v_t) * 1000)::int);
end $function$;
revoke all on function security.aer_course_outcomes_build_v1(text) from public, anon, authenticated;
comment on function security.aer_course_outcomes_build_v1(text) is 'CF-247 AER production closure C1: rebuilds pipeline.aer_course_outcomes (one primary entry-requirement outcome per active course of the entry-read countries) and records the build. Read only on every source table.';

create or replace function security.aer_course_outcomes_refresh_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_last timestamptz;
begin
  select max(b.built_at) into v_last from pipeline.aer_course_outcome_builds b;
  if v_last is not null
     -- fixed: fire guard (the job checks every 5 minutes; a build due now is not put off by a few seconds of start jitter)
     and v_last > clock_timestamp() - make_interval(mins => security.pipeline_num_v1('aer.outcome_register_every_minutes', 60)::int) + interval '30 seconds' then
    return jsonb_build_object('state', 'fresh', 'built_at', v_last);
  end if;
  return security.aer_course_outcomes_build_v1('job');
end $function$;
revoke all on function security.aer_course_outcomes_refresh_v1() from public, anon, authenticated;
comment on function security.aer_course_outcomes_refresh_v1() is 'CF-247 AER production closure C1: job aer-outcome-register; rebuilds the course outcome register when it is older than aer.outcome_register_every_minutes.';

-- 4. the operator read: summary, and pages of rows for Download CSV (rank 4 and above; a direct owner session without claims also answers)
create or replace function public.admin_aer_outcomes(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_rank int := coalesce(security.current_role_rank(), 0); b pipeline.aer_course_outcome_builds%rowtype; v_build jsonb; v_page int; v_off int;
begin
  if (auth.uid() is not null or coalesce(auth.role(), '') <> '') and (auth.uid() is null or v_rank < 4) then
    raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  select * into b from pipeline.aer_course_outcome_builds x order by x.built_at desc limit 1;
  v_build := case when b.built_at is null then jsonb_build_object('built', false)
    else jsonb_build_object('built', true, 'built_at', b.built_at, 'took_ms', b.took_ms, 'courses', b.courses,
      'age_seconds', greatest(round(extract(epoch from now() - b.built_at)), 0)::int,
      'stale', now() - b.built_at > make_interval(mins => security.pipeline_num_v1('aer.outcome_register_stale_after_minutes', 180)::int),
      'refresh_every_minutes', security.pipeline_num_v1('aer.outcome_register_every_minutes', 60)) end;
  if coalesce(p_args->>'part', 'summary') = 'summary' then
    return jsonb_build_object('build', v_build,
      'by_outcome', coalesce((select jsonb_agg(jsonb_build_object('outcome', x.outcome, 'country', x.country, 'courses', x.n, 'published', x.np, 'providers', x.pv) order by x.outcome, x.country)
                                from (select a.outcome, a.country, count(*) n, count(*) filter (where a.provider_published) np, count(distinct a.provider_id) pv
                                        from pipeline.aer_course_outcomes a group by 1, 2) x), '[]'::jsonb),
      'by_detail', coalesce((select jsonb_agg(jsonb_build_object('outcome', x.outcome, 'detail', x.d, 'courses', x.n) order by x.outcome, x.n desc)
                               from (select a.outcome, regexp_replace(a.detail, '\d+', 'N', 'g') d, count(*) n from pipeline.aer_course_outcomes a group by 1, 2) x), '[]'::jsonb));
  end if;
  v_page := least(greatest(coalesce((p_args->>'limit')::int, security.pipeline_num_v1('aer.outcome_register_page_rows', 5000)::int), 1),
                  security.pipeline_num_v1('aer.outcome_register_page_rows', 5000)::int);
  v_off := greatest(coalesce((p_args->>'offset')::int, 0), 0);
  return jsonb_build_object('build', v_build, 'total', (select count(*) from pipeline.aer_course_outcomes), 'offset', v_off, 'limit', v_page,
    'columns', jsonb_build_array('course_id', 'course_code', 'course_title', 'provider', 'provider_published', 'country', 'outcome', 'detail',
                                 'course_url', 'page_status', 'identity_basis', 'read_state', 'read_reason', 'review_item_id', 'built_at'),
    'rows', coalesce((select jsonb_agg(jsonb_build_array(a.course_id, a.course_code, a.course_title, a.provider_name, a.provider_published, a.country, a.outcome, a.detail,
                                                         a.course_url, a.page_status, a.identity_basis, a.read_state, a.read_reason, a.review_item_id, a.built_at)
                                       order by a.country, a.provider_name, a.course_title, a.course_id)
                        from (select * from pipeline.aer_course_outcomes y order by y.country, y.provider_name, y.course_title, y.course_id offset v_off limit v_page) a), '[]'::jsonb));
end $function$;
revoke all on function public.admin_aer_outcomes(jsonb) from public, anon;
grant execute on function public.admin_aer_outcomes(jsonb) to authenticated;
comment on function public.admin_aer_outcomes(jsonb) is 'CF-247 AER production closure C1: the course outcome register for Catalogue › Entry requirements › Resolution inspection: part summary (counts by outcome and country, with build time, age and stale flag) or part rows (a page of rows for Download CSV). Rank 4 and above. Admin read only; never part of the consumer API.';

-- 5. job (G1): catalogued first, then scheduled
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('aer-outcome-register', 'Reports', 62, 'AER course outcome register',
  'Every 5 minutes: rebuilds the course outcome register for academic entry requirements when it is older than its setting (Pipeline settings › Platform upkeep, AER course outcome register: rebuilt every). One build at a time. Read only: it admits, reads, queues and decides nothing. Shown and downloaded on Catalogue › Entry requirements › Resolution inspection.',
  6, false, null)
on conflict (jobname) do nothing;
select cron.schedule('aer-outcome-register', '*/5 * * * *', $$select security.aer_course_outcomes_refresh_v1()$$);

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('job', 'aer-outcome-register', 'Platform', 'Reports', 'AER closure C1: rebuilds the course outcome register', 'active', '{}', '20261030300000'),
 ('table', 'pipeline.aer_course_outcomes', 'Platform', 'Reports', 'AER closure C1: one primary entry-requirement outcome per course (derived)', 'active', '{}', '20261030300000'),
 ('table', 'pipeline.aer_course_outcome_builds', 'Platform', 'Reports', 'AER closure C1: each register build with its count by outcome', 'active', '{}', '20261030300000'),
 ('function', 'security.aer_course_outcomes_build_v1', 'Platform', 'Reports', 'AER closure C1: builds the course outcome register', 'active', '{}', '20261030300000'),
 ('function', 'security.aer_course_outcomes_refresh_v1', 'Platform', 'Reports', 'AER closure C1: job aer-outcome-register (due check)', 'active', '{}', '20261030300000'),
 ('function', 'public.admin_aer_outcomes', 'Platform', 'Reports', 'AER closure C1: the register read and download (rank 4+)', 'active', '{}', '20261030300000')
on conflict do nothing;

-- 6. first build now (the job repeats it), and post-check
select security.aer_course_outcomes_build_v1('migration');
do $$
declare v_courses int; v_reg int;
begin
  select count(*) into v_courses from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
   where c.lifecycle_status = 'active' and coalesce(security.toolset_setting('pipeline', 'entry.course_read_countries'), '["AU"]'::jsonb) ? k.iso_alpha2;
  select count(*) into v_reg from pipeline.aer_course_outcomes;
  if v_reg <> v_courses then raise exception 'C1 post-check: the register holds % courses, % are in scope', v_reg, v_courses; end if;
  if (select count(*) from pipeline.aer_course_outcomes a where a.outcome = 'admitted_course') <>
     (select count(distinct r.course_id) from catalogue.course_entry_requirements r join pipeline.aer_course_outcomes a on a.course_id = r.course_id where r.status = 'active') then
    raise exception 'C1 post-check: admitted course count does not match the active course rows'; end if;
  if not exists (select 1 from cron.job j join pipeline.automation_catalogue a on a.jobname = j.jobname where j.jobname = 'aer-outcome-register' and j.active) then
    raise exception 'C1 post-check: job aer-outcome-register is not scheduled and catalogued'; end if;
  if has_function_privilege('anon', 'public.admin_aer_outcomes(jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.admin_aer_outcomes(jsonb)', 'execute') then
    raise exception 'C1 post-check: grants on admin_aer_outcomes'; end if;
  raise notice 'C1: % courses in the register', v_reg;
end $$;
