-- CF-247 decision W34 (30 Oct 2026, Workstream 3 release health, lane M): cached snapshots and paging fixes for the four slow admin reads.
-- Approved: Platform Admin 30 Oct 2026 06:53 ("Cached snapshots for the four slow admin reads: APPROVED FOR DESIGN AND IMPLEMENTATION").
-- Numbered 20261030050000 provisionally; the integrator renumbers.
-- Why: the weekly deployed run of 30 Oct (01:00 to 01:15 AEDT) had four red tests, all database response time under load:
--   admin_read('providers_page') 3,552 / 3,043 ms and admin_read('courses_page') 3,020 / 3,018 ms against the 3,000 ms budget;
--   admin_read('pipeline_jobs_page') and admin_read('course_coverage') HTTP 500 (statement time-out, signed-in limit 8 s).
-- Causes, measured read-only on 30 Oct 2026 as the Platform Admin (the database was busy; figures are single runs):
--   providers_page: the course count, the adapter status and the evidence count were worked out for every provider (3,085) before the page
--     was chosen, because the window count needs every row (1,722 ms idle).
--   courses_page: every matching course (35,668) was carried with all its columns, the description too, through a window count and a full
--     sort to temporary files (1.0 to 1.6 s idle).
--   pipeline_jobs_page: every job (18,296 shown of 19,657) was projected in full, with a per-job evidence count and a register-run lookup,
--     then sorted (3.8 s idle, 8.1 s when busy).
--   course_coverage: every open re-totalled about 524,000 snapshot rows (6.1 s idle).
-- What:
--   1. course_coverage reads a derived totals snapshot, pipeline.course_coverage_totals (by provider, tier and country: courses per group,
--      attribute states, completeness sums and field sources). It is rebuilt by job course-coverage-snapshot only when one of the hourly
--      source builds has changed, at most once every 'snapshot.course_coverage_min_interval_minutes', one run at a time (advisory try-lock;
--      a second run returns at once and the screens keep the last snapshot). Reads never rebuild, so there is no stampede. The answer is the
--      same as the live re-total (checked read-only for six filter sets) plus 'snapshot': built, checked, stale (after
--      'snapshot.course_coverage_stale_minutes' without a check). The drill-downs stay live and exact.
--   2. providers_page, courses_page and pipeline_jobs_page choose the page on the ids and sort keys only, then read the page's rows in full.
--      Same rows, same order, same fields, same total (checked read-only against the live functions: 7, 8 and 9 argument sets).
--      pipeline_jobs_page hides a register run's earlier batches with one set-based match of the runs (the v2.15.246 Fix 1 rule), helped
--      by a new partial index on pipeline.jobs.
-- Permission checks are unchanged (each function's role check runs first, as before). Read-only and derived: no admission, catalogue or
-- consumer API behaviour changes. The consumer API is not touched (Decision 266): these are admin reads in schema security, new tables in
-- schema pipeline and one index on pipeline.jobs.
-- Rollback: unschedule course-coverage-snapshot; restore the four functions from their definitions at the md5s below (the snapshot branch is
-- skipped when pipeline.course_coverage_snapshot has no row, so emptying it by a paste file also returns course_coverage to the live total).
-- public.admin_read is not edited (live md5 6b1bb9d569bd13390f76803f9a710053): it routes these operations to the functions edited here.
-- Replaces: the live re-total of admin_read('course_coverage') on every open with the derived snapshot pipeline.course_coverage_totals (job course-coverage-snapshot); the full-row window count and sort of providers_page, courses_page and pipeline_jobs_page with page-first reads
-- Retires: nothing (the live re-total stays only as the fallback when no snapshot exists; no table, job or edge function retires)
-- Nothing dropped, deleted or renamed by this migration.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'snapshot.course_coverage_min_interval_minutes', 'Coverage snapshot: rebuild at most every',
  'The coverage totals that Completeness › Courses and Attributes read are rebuilt after an hourly coverage, completeness or field-source build changes, but not more often than this. A shorter time shows changes sooner and uses more database time.', 'number',
  to_jsonb(10), 5, 120, 'minutes', 962, 'Platform upkeep', 'security.course_coverage_snapshot_refresh_v1; job course-coverage-snapshot (every 5 minutes)',
  'CF-247 decision W34 (Platform Admin 30 Oct 2026 06:53): cached snapshot for the slow coverage read'),
 ('pipeline', 'snapshot.course_coverage_stale_minutes', 'Coverage snapshot: shown as stale after',
  'Completeness › Courses and Attributes mark the coverage totals stale when the snapshot has not been checked against the hourly builds for this long (for example when its job has stopped).', 'number',
  to_jsonb(30), 10, 1440, 'minutes', 963, 'Platform upkeep', 'security.admin_course_coverage_read (course_coverage); Completeness › Courses and Attributes',
  'CF-247 decision W34 (Platform Admin 30 Oct 2026 06:53): show snapshot generation time and staleness')
on conflict (toolset_key, key) do nothing;

create table if not exists pipeline.course_coverage_snapshot (
  id smallint primary key default 1 check (id = 1),
  generated_at timestamptz not null,
  checked_at timestamptz not null,
  source_computed_at timestamptz,
  completeness_computed_at timestamptz,
  field_sources_at timestamptz,
  total_rows int not null default 0,
  build_ms int not null default 0
);
comment on table pipeline.course_coverage_snapshot is 'CF-247 W34 (Platform Admin 30 Oct 2026 06:53): one row saying when the coverage totals snapshot (pipeline.course_coverage_totals) was built, when it was last checked against the hourly source builds, and the source build times it was built from; read by security.admin_course_coverage_read, written by security.course_coverage_snapshot_refresh_v1';
alter table pipeline.course_coverage_snapshot enable row level security;
revoke all on table pipeline.course_coverage_snapshot from anon, authenticated;

create table if not exists pipeline.course_coverage_totals (
  kind text not null check (kind in ('group', 'attr', 'completeness', 'source')),
  provider_id uuid,
  tier text,
  country_code text,
  attribute text,
  state text,
  admitted int,
  attributes int,
  n bigint not null,
  sum_completeness numeric,
  sum_accounted numeric,
  max_computed_at timestamptz
);
comment on table pipeline.course_coverage_totals is 'CF-247 W34 (Platform Admin 30 Oct 2026 06:53): derived, read-only coverage totals by provider, tier and country, built from pipeline.course_attribute_coverage, pipeline.course_completeness and pipeline.course_field_source by security.course_coverage_snapshot_refresh_v1 (job course-coverage-snapshot); kind group = courses per group, attr = rows per attribute and state, completeness = courses per admitted and attribute count with sums, source = courses per field and source. admin_read(''course_coverage'') answers from it';
create index if not exists course_coverage_totals_kind_idx on pipeline.course_coverage_totals (kind, country_code, tier);
create index if not exists course_coverage_totals_provider_idx on pipeline.course_coverage_totals (provider_id);
alter table pipeline.course_coverage_totals enable row level security;
revoke all on table pipeline.course_coverage_totals from anon, authenticated;

-- pipeline_jobs_page: the set-based match of register runs to their batches reads this instead of every job of the source
create index if not exists jobs_regulatory_source_created_idx on pipeline.jobs (source_id, created_at) where job_type = 'regulatory_sync';

create or replace function security.course_coverage_snapshot_refresh_v1(p_force boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'pipeline', 'security'
as $function$
-- CF-247 W34 (Platform Admin 30 Oct 2026 06:53): rebuilds pipeline.course_coverage_totals from the three hourly source tables when one of
-- them has been rebuilt since the snapshot, at most once every snapshot.course_coverage_min_interval_minutes; otherwise marks the snapshot
-- checked. One run at a time: a second caller returns at once and the screens keep the last snapshot. Readers never rebuild. The rebuild
-- deletes and inserts in one transaction (no truncate), so a reader always sees the whole previous or the whole new snapshot.
declare
  v_t0 timestamptz := clock_timestamp();
  v_min int := greatest(security.pipeline_num_v1('snapshot.course_coverage_min_interval_minutes', 10)::int, 1);
  v_src timestamptz; v_cc timestamptz; v_fs timestamptz; v_n int;
  v_h pipeline.course_coverage_snapshot%rowtype;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:course_coverage_snapshot')) then  -- fixed: the one-builder lock (W34)
    return jsonb_build_object('skipped', 'busy');
  end if;
  perform set_config('lock_timeout', '2000', true);  -- fixed: technical safety, never queue behind an hourly source build (the next run retries)
  begin
    select max(x.computed_at) into v_src from pipeline.course_attribute_coverage x;
    select max(c.computed_at) into v_cc from pipeline.course_completeness c;
    select max(s.computed_at) into v_fs from pipeline.course_field_source s;
  exception when lock_not_available then
    return jsonb_build_object('skipped', 'source_build_running');
  end;
  select * into v_h from pipeline.course_coverage_snapshot where id = 1;
  if found and not coalesce(p_force, false) then
    if v_h.source_computed_at is not distinct from v_src and v_h.completeness_computed_at is not distinct from v_cc
       and v_h.field_sources_at is not distinct from v_fs then
      update pipeline.course_coverage_snapshot set checked_at = now() where id = 1;
      return jsonb_build_object('skipped', 'current', 'generated_at', v_h.generated_at);
    end if;
    if v_h.generated_at > now() - make_interval(mins => v_min) then
      return jsonb_build_object('skipped', 'min_interval', 'generated_at', v_h.generated_at);
    end if;
  end if;
  delete from pipeline.course_coverage_totals;
  insert into pipeline.course_coverage_totals(kind, provider_id, tier, country_code, attribute, state, admitted, attributes, n, sum_completeness, sum_accounted, max_computed_at)
  select 'group', g.provider_id, g.tier, g.country_code, null::text, null::text, null::int, null::int, count(*)::bigint, null::numeric, null::numeric, null::timestamptz
    from (select distinct x.course_id, x.provider_id, x.tier, x.country_code from pipeline.course_attribute_coverage x) g
   group by g.provider_id, g.tier, g.country_code
  union all
  select 'attr', x.provider_id, x.tier, x.country_code, x.attribute, x.state, null, null, count(*), null, null, null
    from pipeline.course_attribute_coverage x group by x.provider_id, x.tier, x.country_code, x.attribute, x.state
  union all
  select 'completeness', c.provider_id, c.tier, c.country_code, null, null, c.admitted, c.attributes, count(*), sum(c.completeness), sum(c.accounted_pct), max(c.computed_at)
    from pipeline.course_completeness c group by c.provider_id, c.tier, c.country_code, c.admitted, c.attributes
  union all
  select 'source', s.provider_id, s.tier, s.country_code, 'intakes', s.intakes_src, null, null, count(*), null, null, null
    from pipeline.course_field_source s group by s.provider_id, s.tier, s.country_code, s.intakes_src
  union all
  select 'source', s.provider_id, s.tier, s.country_code, 'english', s.english_src, null, null, count(*), null, null, null
    from pipeline.course_field_source s group by s.provider_id, s.tier, s.country_code, s.english_src
  union all
  select 'source', s.provider_id, s.tier, s.country_code, 'fee', s.fee_src, null, null, count(*), null, null, null
    from pipeline.course_field_source s group by s.provider_id, s.tier, s.country_code, s.fee_src;
  get diagnostics v_n = row_count;
  insert into pipeline.course_coverage_snapshot(id, generated_at, checked_at, source_computed_at, completeness_computed_at, field_sources_at, total_rows, build_ms)
  values (1, now(), now(), v_src, v_cc, v_fs, v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000)::int)
  on conflict (id) do update set generated_at = excluded.generated_at, checked_at = excluded.checked_at, source_computed_at = excluded.source_computed_at,
    completeness_computed_at = excluded.completeness_computed_at, field_sources_at = excluded.field_sources_at, total_rows = excluded.total_rows, build_ms = excluded.build_ms;
  return jsonb_build_object('rows', v_n, 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $function$;
revoke all on function security.course_coverage_snapshot_refresh_v1(boolean) from public, anon, authenticated;

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- course_coverage: the snapshot branch, then the live re-total as the fallback (live md5 0485f037236c3859e3c9f757b8a440eb read 30 Oct 2026, lane M)
select pg_temp.edit_n('security.admin_course_coverage_read(text,jsonb)', '0485f037236c3859e3c9f757b8a440eb', array[
  array[$o$  elsif p_operation='course_coverage' then
    with a as ($o$,
        $n$  elsif p_operation='course_coverage' and exists (select 1 from pipeline.course_coverage_snapshot s where s.id=1) then
    -- CF-247 W34 (30 Oct 2026, Platform Admin 06:53): the totals come from the derived snapshot pipeline.course_coverage_totals, rebuilt by
    -- job course-coverage-snapshot after an hourly source build changes (security.course_coverage_snapshot_refresh_v1), never on open.
    -- The same answer as the live re-total below (kept only for a database with no snapshot yet), plus 'snapshot': when it was built and
    -- last checked against the sources, and whether it is stale. Trends and the provider name stay live (small tables); the drill-downs
    -- (course_coverage_courses, course_coverage_providers) stay live and exact. The role check above is unchanged.
    declare v_stale_min int:=greatest(security.pipeline_num_v1('snapshot.course_coverage_stale_minutes',30)::int,1);
    begin
      with t as (select * from pipeline.course_coverage_totals x
                  where (v_tier is null or x.tier=v_tier) and (v_country is null or x.country_code=v_country) and (v_provider is null or x.provider_id=v_provider)),
           h as (select * from pipeline.course_coverage_snapshot where id=1)
      select jsonb_build_object(
        'computed_at',(select h.source_computed_at from h),
        'courses',(select coalesce(sum(t.n),0) from t where t.kind='group'),
        'providers',(select count(distinct t.provider_id) from t where t.kind='group'),
        'tier',v_tier,'country',v_country,
        'provider',case when v_provider is null then null else (select jsonb_build_object('id',p.id,'name',coalesce(p.display_name,p.canonical_name)) from catalogue.providers p where p.id=v_provider) end,
        'countries',(select jsonb_agg(jsonb_build_object('code',country_code,'courses',n,'providers',pn) order by n desc, country_code) from (
            select x.country_code, sum(x.n) n, count(distinct x.provider_id) pn from pipeline.course_coverage_totals x where x.kind='completeness' group by 1) k),
        'attributes',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',states,'total',total) order by ord) from (
            select attribute, jsonb_object_agg(state,n) states, sum(n) total, min(array_position(c_attrs,attribute)) ord
              from (select t.attribute,t.state,sum(t.n) n from t where t.kind='attr' group by 1,2) s group by attribute) x),
        'tiers',(select jsonb_agg(jsonb_build_object('tier',tier,'courses',n,'providers',p) order by tier) from (
            select x.tier, sum(x.n) n, count(distinct x.provider_id) p from pipeline.course_coverage_totals x
             where x.kind='group' and (v_country is null or x.country_code=v_country) group by x.tier) t2),
        -- daily history has no provider dimension: no attribute trend for one provider
        'trend',case when v_provider is null then (select jsonb_agg(jsonb_build_object('date',snapshot_date,'attribute',attribute,'admitted',adm,'total',tot) order by snapshot_date, attribute) from (
            select snapshot_date, attribute, sum(courses) filter (where state='admitted') adm, sum(courses) tot
              from pipeline.course_coverage_daily_by_country where snapshot_date>=current_date-60 and (v_tier is null or tier=v_tier) and (v_country is null or country_code=v_country) group by 1,2) d) end,
        'completeness_states',(select jsonb_agg(jsonb_build_object('attribute',attribute,'states',
              (select jsonb_object_agg(k, coalesce((cs->>k)::int,0)) from unnest(c_states) k),'total',total) order by ord) from (
            select attribute, jsonb_object_agg(cstate,n) cs, sum(n) total, min(array_position(c_attrs,attribute)) ord
              from (select attribute, security.coverage_completeness_state(state) cstate, sum(n) n from (
                      select t.attribute,t.state,sum(t.n) n from t where t.kind='attr' group by 1,2) s0
                    group by 1,2) s group by attribute) x),
        'field_sources',(select jsonb_agg(jsonb_build_object('field',z.field,'source',z.src,'courses',z.n) order by z.field,z.src) from (
            select t.attribute field, t.state src, sum(t.n) n from t where t.kind='source' group by 1,2) z),
        'field_sources_at',(select h.field_sources_at from h),
        'completeness_state_map',(select jsonb_object_agg(s, security.coverage_completeness_state(s))
            from unnest(array['admitted','candidate','in_review','awaiting_l3','not_on_page','in_queue','blocked','page_found','site_known','no_website','missing_l1','no_reader']) s),
        'completeness',(select jsonb_build_object(
              'computed_at',max(c.max_computed_at),
              'courses',coalesce(sum(c.n),0),
              'attributes',max(c.attributes),
              'completeness',round(sum(c.sum_completeness)/nullif(sum(c.n),0),1),
              'accounted_pct',round(sum(c.sum_accounted)/nullif(sum(c.n),0),1),
              'fully_complete',coalesce(sum(c.n) filter (where c.admitted=c.attributes),0),
              'by_admitted',(select jsonb_agg(jsonb_build_object('admitted',b.admitted,'courses',b.n) order by b.admitted) from (
                  select c2.admitted, sum(c2.n) n from t c2 where c2.kind='completeness' group by 1) b),
              'trend',case when v_tier is null then (select jsonb_agg(jsonb_build_object('date',d.snapshot_date,'courses',d.courses,'completeness',d.completeness,
                          'accounted_pct',d.accounted_pct,'fully_complete',d.fully_complete,'computed_at',d.computed_at) order by d.snapshot_date)
                        from pipeline.completeness_daily d where d.snapshot_date>=current_date-60
                         and case when v_provider is not null then d.scope='provider' and d.scope_id=v_provider
                                  when v_country is not null then d.scope='country:'||v_country
                                  else d.scope='platform' end) end)
            from t c where c.kind='completeness'),
        'snapshot',(select jsonb_build_object('source','snapshot','generated_at',h.generated_at,'checked_at',h.checked_at,
              'source_computed_at',h.source_computed_at,'completeness_computed_at',h.completeness_computed_at,'field_sources_at',h.field_sources_at,
              'stale_after_minutes',v_stale_min,'stale',h.checked_at < now() - make_interval(mins => v_stale_min)) from h)
      ) into v;
      return v;
    end;
  elsif p_operation='course_coverage' then
    with a as ($n$],
  array[$o$    ) into v;
    return v;
  elsif p_operation='course_coverage_courses' then$o$,
        $n$    ) into v;
    return v||jsonb_build_object('snapshot',jsonb_build_object('source','live','generated_at',now(),'checked_at',now(),'stale',false));
  elsif p_operation='course_coverage_courses' then$n$]
], array[1,1]);

-- courses_page: page first (live md5 aa10ef7287e7937e476be26c6f157f91 read 30 Oct 2026, lane M)
select pg_temp.edit_n('security.admin_course_page_fast_base(jsonb)', 'aa10ef7287e7937e476be26c6f157f91', array[
  array[$o$  ), numbered as (
    select *,count(*) over() total_count from base
  ), paged as (
    select * from numbered order by
$o$,
        $n$  ), matched as materialized (
    select b.id,b.canonical_title,b.provider_name,b.field_of_study,b.updated_at,b.last_verified_at from base b
  ), numbered as (
    -- CF-247 W34 (30 Oct 2026): the filters run once into the matching ids with their sort keys only; the total is their count and
    -- the page is the ordered ids; the page's rows are then read in full. Before, every matching course was carried with all its
    -- columns (the description too) through a window count and a full sort (1.0 to 1.6 s idle, 3.0 s under load).
    -- Same rows, same order, same fields, same total.
    select k.id,k.ord,(select count(*) from matched) total_count
    from unnest(array(select numbered.id from matched numbered order by
$n$],
  array[$o$      lower(canonical_title),id
    limit v_limit offset v_offset
  ), enriched as ($o$,
        $n$      lower(canonical_title),id
    limit v_limit offset v_offset)) with ordinality k(id,ord)
  ), paged as (
    select
      c.id,c.stable_key,c.canonical_title,c.display_title,c.course_code,c.course_url,
      c.lifecycle_status,c.publication_status,c.last_verified_at,c.created_at,c.updated_at,c.provider_id,
      c.duration_value,c.description,c.delivery_mode canonical_delivery_mode,c.open_to_international,c.open_to_domestic,
      coalesce(p.display_name,p.canonical_name) provider_name,
      co.iso_alpha2::text country_code,co.name country_name,co.default_currency_code::text currency_code,
      sl.code level_code,sl.name level_name,fos.code field_code,fos.name field_of_study,
      n.total_count,n.ord
    from numbered n
    join catalogue.courses c on c.id=n.id
    join catalogue.providers p on p.id=c.provider_id
    join ref.countries co on co.id=p.country_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study fos on fos.id=c.primary_field_id
  ), enriched as ($n$],
  array[$o$      pg.total_count
    from paged pg$o$,
        $n$      pg.total_count,pg.ord
    from paged pg$n$],
  array[$o$    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'),'[]'::jsonb),$o$,
        $n$    'items',coalesce(jsonb_agg(to_jsonb(e)-'total_count'-'ord' order by e.ord),'[]'::jsonb),$n$]
], array[1,1,1,1]);

-- pipeline_jobs_page: page first; the other operations of the function are unchanged (live md5 898e94c53630aee8e22466b121915e8a read 30 Oct 2026, lane M)
select pg_temp.edit_n('security.admin_pipeline_ops_read(text,jsonb)', '898e94c53630aee8e22466b121915e8a', array[
  array[$o$  if p_operation='pipeline_jobs_page' then
    with projected as ($o$,
        $n$  if p_operation='pipeline_jobs_page' then
    -- CF-247 W34 (30 Oct 2026): the filters run once over the jobs without the per-job evidence count or the register-run lookup; the
    -- matching ids and sort keys are counted and the page's ids taken in order; the page's rows are then projected in full with
    -- their evidence count and register-run totals. A register run's earlier batches are hidden by one set-based match of the runs
    -- (the same rule as v2.15.246 Fix 1: the run with the latest start whose window holds the job). Before, every job was projected
    -- in full and sorted (3.8 s idle; the signed-in 8 s limit was passed under load). Same rows, same order, same fields, same total.
    with projected as not materialized ($n$],
  array[$o$uat_ref,j.error_text,
        rq.run_id,rq.run_last_job_id,rq.run_summary
      from pipeline.jobs j$o$,
        $n$uat_ref,j.error_text
      from pipeline.jobs j$n$],
  array[$o$      -- v2.15.246 (Fix 1): a register run's batches are one row (the run's last batch carries the run's totals)
      left join lateral (select q.id run_id, q.actual_job_id run_last_job_id, jsonb_build_object('status', q.status, 'started_at', q.started_at, 'completed_at', q.completed_at, 'expected', q.expected_count, 'processed', q.processed_count, 'created', q.created_count, 'updated', q.updated_count, 'unchanged', q.unchanged_count, 'conflicted', q.conflicted_count, 'failed', q.failed_count, 'register', (select jsonb_build_object('total', pl.register_total, 'new', pl.new_count, 'changed', pl.changed_count, 'departed', pl.departed_count) from pipeline.layer1_run_plans pl where pl.run_id = q.id)) run_summary
                           from pipeline.layer1_run_queue q where j.job_type='regulatory_sync' and q.source_id=j.source_id and q.started_at is not null and j.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds' order by q.started_at desc limit 1) rq on true
    ), filtered as (
      select * from projected x where (x.run_id is null or x.run_last_job_id is null or x.id = x.run_last_job_id) and$o$,
        $n$    ), runs as materialized (
      select distinct on (j.id) j.id, q.actual_job_id run_last_job_id
        from pipeline.layer1_run_queue q join pipeline.jobs j on j.job_type='regulatory_sync' and q.source_id=j.source_id
         and j.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds'
       where q.started_at is not null
       order by j.id, q.started_at desc
    ), filtered as (
      select * from projected x where not exists (select 1 from runs r where r.id=x.id and r.run_last_job_id is not null and r.run_last_job_id<>x.id) and$n$],
  array[$o$    ), numbered as (select f.*,count(*) over()::bigint total_count from filtered f), ordered as (
      select * from numbered order by $o$,
        $n$    ), matched as materialized (select f.id,f.created_at,case when v_sort='duration' then f.duration_ms end duration_ms,f.status,case when v_sort='layer' then f.layer_code end layer_code from filtered f
    ), keys as (
      select k.id,k.ord,(select count(*) from matched)::bigint total_count from unnest(array(select numbered.id from matched numbered order by $n$],
  array[$o$created_at desc,id limit v_limit offset v_offset
    ) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'),'[]'::jsonb),$o$,
        $n$created_at desc,id limit v_limit offset v_offset)) with ordinality k(id,ord)
    ), ordered as (
      select x.*,rq.run_id,rq.run_last_job_id,rq.run_summary,k.total_count,k.ord from keys k join projected x on x.id=k.id
      -- v2.15.246 (Fix 1): a register run's batches are one row (the run's last batch carries the run's totals)
      left join lateral (select q.id run_id, q.actual_job_id run_last_job_id, jsonb_build_object('status', q.status, 'started_at', q.started_at, 'completed_at', q.completed_at, 'expected', q.expected_count, 'processed', q.processed_count, 'created', q.created_count, 'updated', q.updated_count, 'unchanged', q.unchanged_count, 'conflicted', q.conflicted_count, 'failed', q.failed_count, 'register', (select jsonb_build_object('total', pl.register_total, 'new', pl.new_count, 'changed', pl.changed_count, 'departed', pl.departed_count) from pipeline.layer1_run_plans pl where pl.run_id = q.id)) run_summary
                           from pipeline.layer1_run_queue q where x.job_type='regulatory_sync' and q.source_id=x.source_id and q.started_at is not null and x.created_at between q.started_at - interval '5 seconds' and coalesce(q.completed_at, now()) + interval '5 seconds' order by q.started_at desc limit 1) rq on true
    ) select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(o)-'total_count'-'ord' order by o.ord),'[]'::jsonb),$n$]
], array[1,1,1,1,1]);

-- providers_page: page first. The whole function is replaced (same signature, settings and role check) after its live md5 is confirmed.
-- live md5 9ebd485d949649a3959746692efbe511 read 30 Oct 2026, lane M
do $$
begin
  if md5(pg_get_functiondef('security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text)'::regprocedure)) <> '9ebd485d949649a3959746692efbe511' then
    raise exception 'live security.admin_providers_page_v2 differs from the definition this change replaces (md5 %)', md5(pg_get_functiondef('security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text)'::regprocedure));
  end if;
end $$;
create or replace function security.admin_providers_page_v2(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_query text DEFAULT NULL::text, p_country_code text DEFAULT NULL::text, p_subdivision_code text DEFAULT NULL::text, p_lifecycle_status text DEFAULT NULL::text, p_publication_status text DEFAULT NULL::text, p_sort text DEFAULT 'provider'::text, p_direction text DEFAULT 'asc'::text, p_university_group text DEFAULT NULL::text, p_adapter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref', 'pipeline', 'security', 'auth'
AS $function$
declare
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),200);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_sort text:=lower(coalesce(p_sort,'provider'));
  v_dir text:=case when lower(coalesce(p_direction,'asc'))='desc' then 'desc' else 'asc' end;
  v_rank integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  return (
    -- CF-247 W34 (30 Oct 2026): the page is chosen first on the light columns, then the per-provider counts, the adapter status and
    -- the evidence count are worked out for the rows of the page only (they were worked out for every provider before paging: 1.7 s idle,
    -- 3.0 to 3.6 s under load). The adapter status is worked out for every matching provider only when the Adapter filter or the
    -- Adapter sort needs it, and the course count only for the Courses sort. Same rows, same order, same fields.
    with base as (
      select
        p.id,p.display_name,p.canonical_name,c.iso_alpha2::text country_code,c.default_currency_code::text currency_code,
        ps.name subdivision_name,p.primary_city city,p.last_verified_at,p.provider_type_id,
        case when nullif(trim(coalesce(p_adapter,'')),'') is not null or lower(coalesce(p_sort,'provider'))='adapter' then security.provider_adapter_status_v1(p.id) end adapter_status,
        case when lower(coalesce(p_sort,'provider'))='courses' then (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) end course_count
      from catalogue.providers p
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
      where
        (
          nullif(trim(coalesce(p_query,'')),'') is null
          or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.stable_key,'') ilike '%'||trim(p_query)||'%'
          or coalesce(p.primary_city,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.iso_alpha2::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
          or coalesce(c.default_currency_code::text,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.code,'') ilike '%'||trim(p_query)||'%'
          or coalesce(ps.name,'') ilike '%'||trim(p_query)||'%'
        )
        and (nullif(trim(coalesce(p_country_code,'')),'') is null or c.iso_alpha2::text=upper(trim(p_country_code)))
        and (nullif(trim(coalesce(p_subdivision_code,'')),'') is null or ps.code=upper(trim(p_subdivision_code)))
        and (nullif(trim(coalesce(p_lifecycle_status,'')),'') is null or p.lifecycle_status=trim(p_lifecycle_status))
        and (nullif(trim(coalesce(p_publication_status,'')),'') is null or p.publication_status=trim(p_publication_status))
        and (nullif(trim(coalesce(p_university_group,'')),'') is null or p.id in (select security.university_group_provider_ids(p_university_group)))
    ), filtered as (
      select * from base
       where nullif(trim(coalesce(p_adapter,'')),'') is null
          or (p_adapter = 'any' and adapter_status not in ('none', 'no_courses'))
          or adapter_status = p_adapter
    ), numbered as (
      select f.id,count(*) over()::bigint total_count,row_number() over (order by
        case when v_sort='provider' and v_dir='asc' then lower(coalesce(f.display_name,f.canonical_name)) end asc,
        case when v_sort='provider' and v_dir='desc' then lower(coalesce(f.display_name,f.canonical_name)) end desc,
        case when v_sort='country' and v_dir='asc' then f.country_code end asc,
        case when v_sort='country' and v_dir='desc' then f.country_code end desc,
        case when v_sort='currency' and v_dir='asc' then f.currency_code end asc,
        case when v_sort='currency' and v_dir='desc' then f.currency_code end desc,
        case when v_sort='subdivision' and v_dir='asc' then lower(coalesce(f.subdivision_name,'')) end asc,
        case when v_sort='subdivision' and v_dir='desc' then lower(coalesce(f.subdivision_name,'')) end desc,
        case when v_sort='city' and v_dir='asc' then lower(coalesce(f.city,'')) end asc,
        case when v_sort='city' and v_dir='desc' then lower(coalesce(f.city,'')) end desc,
        case when v_sort='type' and v_dir='asc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'~') end asc,
        case when v_sort='type' and v_dir='desc' then coalesce((select pt.name from ref.provider_types pt where pt.id=f.provider_type_id),'') end desc,
        case when v_sort='courses' and v_dir='asc' then f.course_count end asc,
        case when v_sort='courses' and v_dir='desc' then f.course_count end desc,
        case when v_sort='adapter' and v_dir='asc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end asc,
        case when v_sort='adapter' and v_dir='desc' then array_position(array['admitting','testing','building','off','none','no_courses'], f.adapter_status) end desc,
        case when v_sort='verified' and v_dir='asc' then f.last_verified_at end asc nulls first,
        case when v_sort='verified' and v_dir='desc' then f.last_verified_at end desc nulls last,
        lower(coalesce(f.display_name,f.canonical_name)),f.id) ord
      from filtered f
    ), keys as (
      select n.id,n.total_count,n.ord from numbered n where n.ord>v_offset and n.ord<=v_offset+v_limit
    ), page as (
      select
        p.id,p.stable_key,p.canonical_name,p.display_name,
        c.iso_alpha2::text country_code,c.name country_name,c.default_currency_code::text currency_code,
        ps.code subdivision_code,ps.name subdivision_name,ps.subdivision_type,
        p.primary_city city,p.website,p.lifecycle_status,p.publication_status,
        p.last_verified_at,p.created_at,p.updated_at,
        (select pt.code from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_code,
        (select pt.name from ref.provider_types pt where pt.id=p.provider_type_id) provider_type_name,
        p.provider_type_basis,
        exists (select 1 from pipeline.manual_locks ml where ml.entity='provider' and ml.entity_id=p.id and ml.field='provider_type_id') provider_type_locked,
        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        -- 22 Oct 2026 (Platform Admin 11:47): adapter status for the Adapter filter and column
        security.provider_adapter_status_v1(p.id) adapter_status,
        (select count(distinct x.evidence_id)::bigint
           from (
             select e.id evidence_id from pipeline.evidence_artifacts e where e.entity_id=p.id
             union all
             select pi.evidence_id from catalogue.provider_identifiers pi where pi.provider_id=p.id and pi.evidence_id is not null
             union all
             select pr.evidence_id from catalogue.provider_registrations pr where pr.provider_id=p.id and pr.evidence_id is not null
           ) x) evidence_count,
        k.ord
      from keys k
      join catalogue.providers p on p.id=k.id
      join ref.countries c on c.id=p.country_id
      left join ref.subdivisions ps on ps.id=p.subdivision_id
    )
    select jsonb_build_object(
      'items',coalesce((select jsonb_agg((to_jsonb(o)-'ord')||jsonb_build_object('university_groups',security.provider_university_groups(o.id)) order by o.ord) from page o),'[]'::jsonb),
      'total',coalesce((select max(total_count) from keys),0),
      'limit',v_limit,
      'offset',v_offset,
      'sort',v_sort,
      'direction',v_dir
    )
  );
end
$function$;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('course-coverage-snapshot', 'Reports', 21, 'Coverage totals snapshot',
  'Every 5 minutes: when the hourly coverage, completeness or field-source build has changed, rebuilds the coverage totals that Completeness › Courses and Attributes read, at most once every "Coverage snapshot: rebuild at most every" minutes; otherwise marks the snapshot checked. One run at a time: a second run returns at once and the screens keep the last snapshot. Read-only and derived: nothing in the catalogue changes.',
  5, false, null)
on conflict (jobname) do nothing;
select cron.schedule('course-coverage-snapshot', '2-59/5 * * * *', 'select security.course_coverage_snapshot_refresh_v1()');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('job', 'course-coverage-snapshot', 'Platform', 'W34: rebuilds the coverage totals snapshot after an hourly source build changes', 'active', '{}', '20261030050000'),
 ('table', 'pipeline.course_coverage_snapshot', 'Platform', 'W34: when the coverage totals snapshot was built and last checked', 'active', '{}', '20261030050000'),
 ('table', 'pipeline.course_coverage_totals', 'Platform', 'W34: derived coverage totals that admin_read(course_coverage) answers from', 'active', '{}', '20261030050000'),
 ('function', 'security.course_coverage_snapshot_refresh_v1', 'Platform', 'W34: single-flight rebuild of the coverage totals snapshot (job course-coverage-snapshot)', 'active', '{}', '20261030050000')
on conflict do nothing;

-- the first snapshot now (the job keeps it current); if a source build holds its table, the read uses the live total until the next run
select security.course_coverage_snapshot_refresh_v1(true);

-- post-check
do $$
declare v text;
begin
  v := pg_get_functiondef('security.admin_course_coverage_read(text,jsonb)'::regprocedure);
  if position('pipeline.course_coverage_totals' in v) = 0 or position('''source'',''live''' in v) = 0 then raise exception 'W34 post-check: course_coverage snapshot branch missing'; end if;
  v := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
  if position('matched as materialized' in v) = 0 or position('with ordinality k(id,ord)' in v) = 0 then raise exception 'W34 post-check: courses_page page-first missing'; end if;
  v := pg_get_functiondef('security.admin_pipeline_ops_read(text,jsonb)'::regprocedure);
  if position('runs as materialized' in v) = 0 or position('matched as materialized' in v) = 0 then raise exception 'W34 post-check: pipeline_jobs_page page-first missing'; end if;
  v := pg_get_functiondef('security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text)'::regprocedure);
  if position('keys as (' in v) = 0 or position('CF-247 W34' in v) = 0 then raise exception 'W34 post-check: providers_page page-first missing'; end if;
  if not exists (select 1 from cron.job where jobname = 'course-coverage-snapshot' and command = 'select security.course_coverage_snapshot_refresh_v1()') then raise exception 'W34 post-check: job course-coverage-snapshot not scheduled as written'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'course-coverage-snapshot') then raise exception 'W34 post-check: job not catalogued'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('snapshot.course_coverage_min_interval_minutes', 'snapshot.course_coverage_stale_minutes')) <> 2 then raise exception 'W34 post-check: settings missing'; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'pipeline' and indexname = 'jobs_regulatory_source_created_idx') then raise exception 'W34 post-check: jobs index missing'; end if;
  if not exists (select 1 from pipeline.course_coverage_snapshot where id = 1) then raise notice 'W34 post-check: first snapshot not built yet (a source build held its table); the job builds it within 5 minutes'; end if;
end $$;
