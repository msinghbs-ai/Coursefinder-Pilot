-- CF-247 s1014 (S1-Build; Platform Admin 23 Nov 2026 22:55 AEDT, approved subject to measured plan validation): the Courses keyword search
-- uses trigram indexes. Deployed UAT cf-061 failed because a keyword search took 2.5 to 3.5 s quiet and 7.2 to 8.2 s under load, beyond the
-- test's 6 s wait and near the 8 s signed-in limit; the data was correct (RMIT Advanced Diploma of Accounting, 113126B, row 22 of 53).
-- Cause (EXPLAIN ANALYZE, live, rolled back): security.admin_course_page_fast_base tests the keyword as one OR across the course title,
-- display title, provider name, code, stable key and StudySearch identifier; with ilike '%...%' and no trigram support the planner reads all
-- 44,734 courses and 3,106 providers for every keyword (734.7 ms for the filter alone, more under load).
-- 1. pg_trgm in the extensions schema (version 1.6, Supabase-provided).
-- 2. Four GIN trigram indexes, one per course column the keyword is tested against (the provider name is read from the 3,106 providers and
--    joined by provider id; the identifier keeps its existing prefix index). Each is used by the new plan (Bitmap Index Scan per column).
--    Rehearsed sizes and build times: title 5,496 kB 6.9 s, display title 5,496 kB 4.2 s, code 2,552 kB 1.6 s, stable key 5,136 kB 4.0 s,
--    each built inside a short lock retry.
-- 3. security.admin_course_page_fast_base (live md5 97635329, s977; md5-guarded): only the keyword test changes. It becomes one lookup per
--    column (query_hits, a union of the same six tests), and the list keeps the courses found. The same tests, so the same courses match;
--    filters, sort, paging, totals and the role check are untouched (the rest of the body is copied from the live definition, not retyped).
-- Measured (rolled back, live, scheduled jobs running; admin_read('courses_page') twice, first and second call):
--   code 113126B 1,471/314 -> 315/63 ms; provider "RMIT" 6,456/3,660 -> 1,035/207 ms; title "Advanced Diploma of Accounting" 4,059/3,031 ->
--   783/168 ms; partial "Accounting" 2,942/988 -> 642/152 ms; no keyword, AU, NZ and CA lists unchanged (same plan). All eight lists: identical
--   totals and the same course ids in the same order (md5 of the ordered ids); 113126B row 1 and row 22 as before.
-- 4. Source record for public.admin_toolsets_read (Platform Admin 23 Nov 2026 22:59): the function exists live only, with no migration in
--    this repository (a governance gap found while tracing its timeouts, fixed by s1013's indexes). Its exact production definition is kept
--    here, guarded by its live md5 (df2380c6) before and after, so this records it without changing it.
-- G1: no job. G2: no operational value. G3: no consumer object changed (checked before and after; v2 and v3 untouched).
-- Manual locks and active cron jobs checked unchanged. Nothing dropped or deleted.
-- Replaces: the single OR keyword test in security.admin_course_page_fast_base (rewritten in place).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads and the function change

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure), chr(13), '')) <> '976353299ff36e0f5c671420eb526e30' then
    raise exception 'guard: live security.admin_course_page_fast_base differs from the definition this change edits';
  end if;
end $g$;
create temp table s1014_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1014_cron on commit drop as select count(*) n from cron.job where active;

create extension if not exists pg_trgm with schema extensions;

do $i$
declare v_sql text; v_try int;
begin
  foreach v_sql in array array[
    'create index if not exists courses_title_trgm_idx on catalogue.courses using gin (canonical_title extensions.gin_trgm_ops)',
    'create index if not exists courses_display_title_trgm_idx on catalogue.courses using gin ((coalesce(display_title, '''')) extensions.gin_trgm_ops)',
    'create index if not exists courses_code_trgm_idx on catalogue.courses using gin ((coalesce(course_code, '''')) extensions.gin_trgm_ops)',
    'create index if not exists courses_stable_key_trgm_idx on catalogue.courses using gin ((coalesce(stable_key, '''')) extensions.gin_trgm_ops)'] loop
    v_try := 0;
    loop
      begin
        perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
        execute v_sql;
        exit;
      exception when lock_not_available then
        v_try := v_try + 1;
        if v_try >= 5 then raise exception 'could not take the lock for: %', v_sql; end if;  -- fixed: tries before giving up
        perform pg_sleep(2);  -- fixed: pause between tries
      end;
    end loop;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $i$;
analyze catalogue.courses;

do $f$
declare d text := pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure);
  v_old_where text := $blk$    where (nullif(trim(coalesce(p_args->>'query','')),'') is null
      or c.canonical_title ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'
      or coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
      or exists(select 1 from catalogue.course_identifiers ci where ci.course_id=c.id and ci.scheme='studysearch' and upper(ci.identifier) like upper(trim(p_args->>'query'))||'%'))
$blk$;
  v_new_where text := $blk$    where (nullif(trim(coalesce(p_args->>'query','')),'') is null or c.id in (select h.id from query_hits h))
$blk$;
  v_old_cte text := $blk$  ), base as (
    select
      c.id,c.stable_key,c.canonical_title$blk$;
  v_new_cte text := $blk$  ), query_hits as materialized (
    -- s1014 (S1-Build, Platform Admin 23 Nov 2026 22:55): the keyword test as one lookup per column, each served by its trigram index
    -- (pg_trgm), instead of one OR across courses and providers that read every course. Same tests, so the same courses match.
    select c.id from catalogue.courses c where nullif(trim(coalesce(p_args->>'query','')),'') is not null and c.canonical_title ilike '%'||trim(p_args->>'query')||'%'
    union select c.id from catalogue.courses c where nullif(trim(coalesce(p_args->>'query','')),'') is not null and coalesce(c.display_title,'') ilike '%'||trim(p_args->>'query')||'%'
    union select c.id from catalogue.courses c where nullif(trim(coalesce(p_args->>'query','')),'') is not null and coalesce(c.course_code,'') ilike '%'||trim(p_args->>'query')||'%'
    union select c.id from catalogue.courses c where nullif(trim(coalesce(p_args->>'query','')),'') is not null and coalesce(c.stable_key,'') ilike '%'||trim(p_args->>'query')||'%'
    union select c.id from catalogue.courses c join catalogue.providers p on p.id=c.provider_id where nullif(trim(coalesce(p_args->>'query','')),'') is not null and coalesce(p.display_name,p.canonical_name,'') ilike '%'||trim(p_args->>'query')||'%'
    union select ci.course_id from catalogue.course_identifiers ci where nullif(trim(coalesce(p_args->>'query','')),'') is not null and ci.scheme='studysearch' and upper(ci.identifier) like upper(trim(p_args->>'query'))||'%'
  ), base as (
    select
      c.id,c.stable_key,c.canonical_title$blk$;
begin
  if (length(d) - length(replace(d, v_old_where, ''))) / length(v_old_where) <> 1 then raise exception 'guard: the keyword test is not found exactly once'; end if;
  if (length(d) - length(replace(d, v_old_cte, ''))) / length(v_old_cte) <> 1 then raise exception 'guard: the base list is not found exactly once'; end if;
  execute replace(replace(d, v_old_where, v_new_where), v_old_cte, v_new_cte);
end $f$;

do $r$
begin
  if md5(pg_get_functiondef('public.admin_toolsets_read()'::regprocedure)) <> 'df2380c6d541db3756bcc88c5e62641a' then
    raise exception 'guard: live public.admin_toolsets_read differs from the production definition recorded here';
  end if;
end $r$;

-- public.admin_toolsets_read: production definition, recorded as read on 23 Nov 2026 (unchanged)
CREATE OR REPLACE FUNCTION public.admin_toolsets_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object('can_manage', v_rank >= 6,
    'toolsets', (select coalesce(jsonb_agg(jsonb_build_object('key', t.key, 'label', t.label, 'kind', t.kind, 'layers', t.layers, 'enforcement', t.enforcement, 'help', t.help,
        'updated_at', t.updated_at, 'reason', t.reason,
        'key_saved', (select p.vault_secret_id is not null from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'switched_on', (select p.enabled from pipeline.layer2_acquisition_providers p where p.provider_key = t.provider_key),
        'plan', case when exists (select 1 from pipeline.platform_toolset_settings s where s.toolset_key = t.key and s.key = 'plan_credits') then security.toolset_plan_status(t.key) end,
        'settings', (select coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'help', s.help, 'kind', s.kind, 'value', s.value, 'min', s.min_value, 'max', s.max_value,
                        'unit', s.unit, 'home', s.home, 'home_group', s.home_group, 'section', s.section, 'updated_at', s.updated_at, 'reason', s.reason) order by s.sort, s.key), '[]'::jsonb)
                     from pipeline.platform_toolset_settings s where s.toolset_key = t.key)) order by t.sort), '[]'::jsonb)
      from pipeline.platform_toolsets t where t.key <> 'pipeline'),  -- v2.15.269: the register shows on Pipeline settings
    'openrouter', jsonb_build_object(
      'balance', (select jsonb_build_object('remaining_usd', o.remaining_usd, 'observed_at', o.observed_at, 'total_credits', o.payload->'total_credits', 'total_usage', o.payload->'total_usage')
                  from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
      -- v2.15.258 (bug 12/10-01): the AI uses that run now, with their daily guards and the credit floor (Layer 3 retired)
      'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
      'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                    'allowed', security.ai_use_allowed_v1(g.use))), '[]'::jsonb) from security.ai_spend_today_v1() g),
      'spend_by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'usd', d.usd, 'calls', d.calls) order by d.day), '[]'::jsonb)
                       from (select r.day, round(sum(r.usd), 4) usd, sum(r.calls) calls from (
                               select (x.at at time zone 'UTC')::date as day, sum(x.cost_usd) usd, count(*) calls from pipeline.scholarship_ai_extractions x where x.at > now() - interval '14 days' group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.uni_adapter_drafts x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (x.created_at at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.central_ai_queue x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1
                               union all select (coalesce(x.decided_at, x.created_at) at time zone 'UTC')::date, sum(x.cost_usd), count(*) from pipeline.coverage_ai_match x where x.created_at > now() - interval '14 days' and coalesce(x.cost_usd, 0) > 0 group by 1) r
                             group by 1) d)),
    'job_layers', (select coalesce(jsonb_object_agg(l.jobname, l.layer), '{}'::jsonb) from pipeline.platform_job_layers l));
end $function$
;

do $post$
declare v_api jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1014_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1014_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if md5(replace(pg_get_functiondef('security.admin_course_page_fast_base(jsonb)'::regprocedure), chr(13), '')) <> '22eb2f5e78def853193e672808628e69' then
    raise exception 'post-check: security.admin_course_page_fast_base is not the rehearsed definition';
  end if;
  if md5(pg_get_functiondef('public.admin_toolsets_read()'::regprocedure)) <> 'df2380c6d541db3756bcc88c5e62641a' then
    raise exception 'post-check: public.admin_toolsets_read changed';
  end if;
  if to_regclass('catalogue.courses_title_trgm_idx') is null or to_regclass('catalogue.courses_display_title_trgm_idx') is null
     or to_regclass('catalogue.courses_code_trgm_idx') is null or to_regclass('catalogue.courses_stable_key_trgm_idx') is null then
    raise exception 'post-check: a trigram index is missing';
  end if;
end $post$;
