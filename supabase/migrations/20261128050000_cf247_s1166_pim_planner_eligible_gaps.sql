-- CF-247 s1166 (S1-RM-Design; Global Autonomous PIM step 3, planner integration and eligible next-action selection; Platform Admin 25 Nov 2026 18:49 and 21:37).
--   security.enrich_plan_priority_v1 (the provider list the existing planner reads) now counts a gap only when it is eligible to be worked:
--     not admitted, a reader exists (state no_reader is a field nobody can read yet), the field applies to the course (register rule: country, course open to international students),
--     no recorded not_applicable absence, and no evidenced no-source finding whose revisit is not yet due (course_field_absence.next_eligible_at in the future).
--   A provider with no eligible gap leaves the list, so the planner no longer plans runs that cannot gain anything. A provider returns when a revisit falls due, because the test reads the clock.
--   New providers and courses are enrolled by the existing coverage build (security.course_coverage_build_v1: every active course already has coverage rows; the 9 courses created in the last 7 days
--   are covered), which this change does not touch.
--   Signature, columns and the callers (security.enrich_plan_auto_v1, the planner screens) are unchanged. Performance read live before writing: 5.8 s for the 530,431-row coverage table.
-- G1: no job. G2: no operational value. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: the live security.enrich_plan_priority_v1 (create or replace; md5 366ff12040bac05d4e494956319a2b76). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace
set local statement_timeout = '120s';  -- fixed: the guard reads and the two measured runs

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.enrich_plan_priority_v1()'::regprocedure)) <> '366ff12040bac05d4e494956319a2b76' then
    raise exception 'guard: security.enrich_plan_priority_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1166_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1166_cron on commit drop as select count(*) n from cron.job where active;
create temp table s1166_before on commit drop as select * from security.enrich_plan_priority_v1();

create or replace function security.enrich_plan_priority_v1()
returns table(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank integer)
language sql
stable
security definer
set search_path = ''
as $f$
  select a.provider_id, max(coalesce(p.display_name, p.canonical_name)), max(a.country_code), count(distinct a.course_id),
         count(*) filter (where e.eligible),
         (select min(coalesce(o.rank_low, o.rank_exact)) from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id where l.provider_id = a.provider_id)
    from pipeline.course_attribute_coverage a join pipeline.field_register r on r.field = a.attribute and r.reader in ('coverage', 'enrich')
    join catalogue.providers p on p.id = a.provider_id
    join catalogue.courses c on c.id = a.course_id
    cross join lateral (
      select a.state not in ('admitted', 'no_reader')
         and not (r.applicability_rule = 'countries' and not (r.applicability_param->'countries') ? a.country_code)
         and not (r.applicability_requires = 'international_open' and c.open_to_international is false)
         and not exists (select 1 from pipeline.course_field_absence ab
                          where ab.course_id = a.course_id and ab.field = r.absence_field and ab.resolved_at is null
                            and (ab.absence_class = 'not_applicable' or ab.next_eligible_at > now())) as eligible) e
   where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)
   group by a.provider_id
  having count(*) filter (where e.eligible) > 0
$f$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); v_n int; t0 timestamptz := clock_timestamp(); v_after int; v_before int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1166_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1166_cron) then raise exception 'guard: active cron jobs changed'; end if;
  create temp table s1166_after on commit drop as select * from security.enrich_plan_priority_v1();
  select count(*) into v_before from s1166_before; select count(*) into v_after from s1166_after;
  -- never adds a provider, never raises a count: the new list is the old list with ineligible gaps taken out
  select count(*) into v_n from s1166_after n left join s1166_before o on o.provider_id = n.provider_id where o.provider_id is null or n.missing > o.missing or n.courses <> o.courses;
  if v_n <> 0 then raise exception 'guard: % providers are new or have a higher count than before', v_n; end if;
  raise notice 'providers before %, after %; run % ms', v_before, v_after, (extract(epoch from clock_timestamp() - t0) * 1000)::int;  -- fixed: counts and milliseconds
end $c$;
