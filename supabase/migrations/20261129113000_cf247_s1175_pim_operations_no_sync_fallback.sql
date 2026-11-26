-- CF-247 s1175 (S1-RM-Design; SS-Programme-Control 26 Nov 2026 15:05 AEDT): outstanding PIM backend interfaces on the existing background snapshot, and no synchronous fallback.
--   1. security.data_delivery_v1: a missing Data Delivery helper snapshot now returns null (its age and error stay in key snapshots); the screen read never counts a helper live.
--   2. security.pim_operations_v1(), counted in the background with the PIM snapshot (pim.operations):
--        workers: every active scheduled job with its last start, last success, failures and running flag from the existing job summary (pipeline.data_delivery_job_runs.runs),
--                 stalled when it has not succeeded within plans.auto_stall_hours (existing setting); expired field-enrich leases counted;
--        freshness_by_country: by country and course field, held values and those past their refresh window (pim.refresh_days or the field's own);
--        consumer: the existing verified consumer read-back readings (pipeline.data_delivery_readings, measure consumer) with their time and error.
--   Request register and request feedback outcomes: no registered database source holds the StudySearch request register (it is kept by the requirements register outside the
--   database), so they are not projected here; recorded as a dependency.
-- G1: no job. G2: existing settings. G3: no consumer API object touched (checked). No lock removed; cron ceiling checked. Read-only closing checks.
-- Replaces: the s1174 fallback in security.data_delivery_v1; the s1170 snapshot expression in security.data_delivery_refresh_v1 (one key added).
-- Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the read-only checks

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
end $g$;
create temp table s1175_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $s$
declare d text := pg_get_functiondef('security.data_delivery_v1()'::regprocedure); h text; a text;
begin
  foreach h in array array['cdesc_stages', 'pdesc', 'intake', 'aer'] loop
    a := format('coalesce((select x.rows from pipeline.data_delivery_helper_snapshots x where x.helper = %L), security.data_delivery_%s_v1())', h, h);
    if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: % fallback not found exactly once', h; end if;
    d := replace(d, a, format('coalesce((select x.rows from pipeline.data_delivery_helper_snapshots x where x.helper = %L), ''null''::jsonb)', h));
  end loop;
  execute d;
end $s$;

create or replace function security.pim_operations_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with st as (select security.pipeline_num_v1('plans.auto_stall_hours', 2)::int h, security.pipeline_num_v1('pim.refresh_days', 365)::int d),
  jr as (select j.runs, j.measured_at from pipeline.data_delivery_job_runs j where j.singleton),
  w as (
    select c.jobname, c.schedule, (r.value->>'last_start')::timestamptz last_start, (r.value->>'last_success')::timestamptz last_success,
           coalesce((r.value->>'failed')::int, 0) failed_24h, coalesce((r.value->>'running')::boolean, false) running
      from cron.job c join jr on true left join lateral jsonb_each(coalesce(jr.runs, '{}'::jsonb)) r on r.key = c.jobname
     where c.active and r.key is not null),
  f as (
    select k.iso_alpha2 cc, a.attribute field, count(*) held,
           count(*) filter (where co.last_verified_at is null or co.last_verified_at < now() - make_interval(days => coalesce(fr.refresh_days, st.d))) refresh_due
      from pipeline.course_attribute_coverage a cross join st
      join pipeline.field_register fr on fr.field = a.attribute
      join catalogue.courses co on co.id = a.course_id and co.lifecycle_status = 'active'
      join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
     where a.state = 'admitted' and not exists (select 1 from security.provider_hidden_v1 x where x.provider_id = p.id)
     group by 1, 2)
  select jsonb_build_object(
    'as_at', now(),
    'jobs_summary_at', (select measured_at from jr),
    'workers', coalesce((select jsonb_agg(jsonb_build_object('job', jobname, 'schedule', schedule, 'last_start', last_start, 'last_success', last_success, 'failed_24h', failed_24h, 'running', running,
                         'stalled', last_success is null or last_success < now() - make_interval(hours => (select h from st))) order by jobname) from w), '[]'::jsonb),
    'stalled_workers', (select count(*) from w where last_success is null or last_success < now() - make_interval(hours => (select h from st))),
    'expired_leases', (select count(*) from pipeline.field_enrich_items e where e.state in ('leased', 'ai') and e.leased_until < now()),
    'freshness_by_country', coalesce((select jsonb_agg(jsonb_build_object('country', cc, 'field', field, 'held', held, 'refresh_due', refresh_due) order by cc, field) from f), '[]'::jsonb),
    'consumer', coalesce((select jsonb_agg(jsonb_build_object('stream', r.stream, 'rows', r.rows, 'measured_at', r.measured_at, 'error', r.error) order by r.stream)
                            from pipeline.data_delivery_readings r where r.measure = 'consumer'), '[]'::jsonb),
    'requests', jsonb_build_object('status', 'not_projected', 'reason', 'No registered database source holds the StudySearch request register; it is kept by the requirements register outside the database.'),
    'meaning', 'Workers come from the existing scheduled-job summary; stalled means no success within plans.auto_stall_hours. Consumer figures are the existing verified read-back of what the website and Zoho read.')
$f$;
comment on function security.pim_operations_v1() is 'PIM (s1175): workers and stalls, freshness by country, verified consumer read-back; counted into the Data Delivery snapshot (pim.operations).';
revoke all on function security.pim_operations_v1() from public, anon, authenticated;
grant execute on function security.pim_operations_v1() to service_role;

do $r$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := E'''refresh'', security.pim_refresh_v1())';
        b constant text := E'''refresh'', security.pim_refresh_v1(), ''operations'', security.pim_operations_v1())';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: snapshot anchor not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); o jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1175_locks) then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  if position('security.data_delivery_cdesc_stages_v1()' in pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) > 0 then raise exception 'guard: a live helper count is left in the screen read'; end if;
  o := security.pim_operations_v1();
  if jsonb_array_length(o->'freshness_by_country') = 0 or jsonb_array_length(o->'consumer') = 0 then raise exception 'guard: operations read empty: %', left(o::text, 300); end if;
  raise notice 'workers %, stalled %', jsonb_array_length(o->'workers'), o->'stalled_workers';
end $c$;
