-- CF-247 s1167 (S1-RM-Design; Global Autonomous PIM, F-OPS.21 and step 3; Platform Admin 25 Nov 2026 23:12 AEDT: "Do not allow the monitoring query to delay the existing Admin UI.
-- Reuse existing snapshot mechanisms where appropriate." and "Preserve excluded-gap reasons and automatic reconsideration when eligibility changes.").
--   1. The PIM progress is counted in the background by the existing Data Delivery count (security.data_delivery_refresh_v1, job data-delivery, every minute, counts again after
--      data_delivery.refresh_minutes) into the existing singleton pipeline.data_delivery_job_runs (new columns pim, pim_measured_at, pim_took_ms, pim_error, pim_failed_at).
--      security.data_delivery_v1 reads that snapshot (with its time and any error) instead of running security.pim_progress_v1 on every screen read (6 s warm, 32 s cold).
--      A failed count never overwrites the last good one, as for the other Data Delivery counts.
--   2. security.pim_excluded_gaps_v1(): every non-admitted course field gap by field and the reason it is or is not worked now: no_reader, country_not_covered, closed_to_international,
--      recorded_not_applicable, no_source_revisit_pending (with the earliest revisit), eligible_unconfirmed, eligible. Nothing is removed from coverage: a gap leaves the planner only
--      while its reason holds, and comes back by itself when it stops holding (the planner tests the clock and the current flags on every read). Snapshot key pim.excluded.
--   3. Fix to s1166 (found by this change's agreement check): the planner dropped 337 eligible gaps of courses closed to international students on fields with no international rule,
--      because a null rule made the eligibility test null. The tests are now null-safe: an unknown country is not covered (as in security.field_applicable_v1), a field with no
--      international rule is not excluded by it.
-- G1: no new job (the existing data-delivery job). G2: the count-again time is the existing setting. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: the s1166 security.enrich_plan_priority_v1 (null-safe tests); the s1162 live call of security.pim_progress_v1 inside security.data_delivery_v1. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the column add and function replaces
set local statement_timeout = '120s';  -- fixed: the first snapshot count (about 10 to 40 s) and the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) <> '5f5f1bd84808ce59d587f7d1a419697d' then
    raise exception 'guard: security.data_delivery_refresh_v1 is not the definition this change was written against';
  end if;
  if md5(pg_get_functiondef('security.enrich_plan_priority_v1()'::regprocedure)) <> '7315bd917461d96caf0c9960756d35be' then
    raise exception 'guard: security.enrich_plan_priority_v1 is not the s1166 definition';
  end if;
  if md5(pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) <> 'd84480a5d78ee11e204b305fdb2d9787' then
    raise exception 'guard: security.data_delivery_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1167_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1167_cron on commit drop as select count(*) n from cron.job where active;

alter table pipeline.data_delivery_job_runs
  add column if not exists pim jsonb,
  add column if not exists pim_measured_at timestamptz,
  add column if not exists pim_took_ms integer,
  add column if not exists pim_error text,
  add column if not exists pim_failed_at timestamptz;
comment on column pipeline.data_delivery_job_runs.pim is 'PIM progress snapshot (s1167): security.pim_progress_v1 with key excluded (security.pim_excluded_gaps_v1), counted by security.data_delivery_refresh_v1.';
comment on column pipeline.data_delivery_job_runs.pim_measured_at is 'When the PIM snapshot was last counted successfully.';
comment on column pipeline.data_delivery_job_runs.pim_took_ms is 'How long the last PIM count took, in milliseconds.';
comment on column pipeline.data_delivery_job_runs.pim_error is 'The error of the last failed PIM count (the last good snapshot stays).';
comment on column pipeline.data_delivery_job_runs.pim_failed_at is 'When the last PIM count failed.';

create or replace function security.enrich_plan_priority_v1()
returns table(provider_id uuid, name text, country text, courses bigint, missing bigint, best_rank integer)
language sql
stable
security definer
set search_path = ''
as $p$
  select a.provider_id, max(coalesce(p.display_name, p.canonical_name)), max(a.country_code), count(distinct a.course_id),
         count(*) filter (where e.eligible),
         (select min(coalesce(o.rank_low, o.rank_exact)) from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id where l.provider_id = a.provider_id)
    from pipeline.course_attribute_coverage a join pipeline.field_register r on r.field = a.attribute and r.reader in ('coverage', 'enrich')
    join catalogue.providers p on p.id = a.provider_id
    join catalogue.courses c on c.id = a.course_id
    cross join lateral (
      select coalesce(a.state not in ('admitted', 'no_reader'), false)
         and not (r.applicability_rule = 'countries' and not coalesce((r.applicability_param->'countries') ? a.country_code, false))
         and not (coalesce(r.applicability_requires = 'international_open', false) and c.open_to_international is false)
         and not exists (select 1 from pipeline.course_field_absence ab
                          where ab.course_id = a.course_id and ab.field = r.absence_field and ab.resolved_at is null
                            and (ab.absence_class = 'not_applicable' or ab.next_eligible_at > now())) as eligible) e
   where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)
   group by a.provider_id
  having count(*) filter (where e.eligible) > 0
$p$;

create or replace function security.pim_excluded_gaps_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $f$
  with g as (
    select a.attribute as field,
           case when a.state = 'no_reader' then 'no_reader'
                when r.applicability_rule = 'countries' and not coalesce((r.applicability_param->'countries') ? a.country_code, false) then 'country_not_covered'  -- an unknown country is not covered, as in security.field_applicable_v1
                when r.applicability_requires = 'international_open' and c.open_to_international is false then 'closed_to_international'
                when ab.absence_class = 'not_applicable' then 'recorded_not_applicable'
                when ab.next_eligible_at > now() then 'no_source_revisit_pending'
                when r.applicability_status <> 'defined' or (r.applicability_requires = 'international_open' and c.open_to_international is null) then 'eligible_unconfirmed'
                else 'eligible' end as reason,
           ab.next_eligible_at
      from pipeline.course_attribute_coverage a
      join pipeline.field_register r on r.field = a.attribute and r.reader in ('coverage', 'enrich')
      join catalogue.providers pv on pv.id = a.provider_id
      join catalogue.courses c on c.id = a.course_id
      left join lateral (select x.absence_class, x.next_eligible_at from pipeline.course_field_absence x
                          where x.course_id = a.course_id and x.field = r.absence_field and x.resolved_at is null
                            and (x.absence_class = 'not_applicable' or x.next_eligible_at > now())
                          order by (x.absence_class = 'not_applicable') desc, x.next_eligible_at desc limit 1) ab on true
     where a.state <> 'admitted' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = a.provider_id)),
  f as (select field, reason, count(*) as n, min(next_eligible_at) as next_revisit from g group by field, reason)
  select jsonb_build_object(
    'as_at', now(),
    'totals', coalesce((select jsonb_object_agg(reason, n) from (select reason, sum(n) as n from f group by reason) t), '{}'::jsonb),
    'by_field', coalesce((select jsonb_agg(jsonb_build_object('field', field, 'reason', reason, 'gaps', n, 'next_revisit', next_revisit) order by field, reason) from f), '[]'::jsonb),
    'meaning', 'Non-admitted course field gaps by why they are or are not worked now. Only eligible and eligible_unconfirmed are planned; the others come back by themselves when their reason stops holding (a revisit falls due, a flag or rule changes). Excluded gaps are workload, not delivered data.')
$f$;
comment on function security.pim_excluded_gaps_v1() is 'PIM (s1167): non-admitted course field gaps by field and reason (eligible or why not), with the earliest revisit; counted into the Data Delivery snapshot.';
revoke all on function security.pim_excluded_gaps_v1() from public, anon, authenticated;
grant execute on function security.pim_excluded_gaps_v1() to service_role;

-- the background count: one more snapshot in the existing count, due on the same count-again time
do $r$
declare d text := pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure);
        a constant text := E'  for m in\n    select d.stream, d.measure';
        b constant text := E'  -- PIM progress (s1167): counted here in the background, so the Data Delivery read only reads the snapshot\n'
          || E'  if p_force or not exists (select 1 from pipeline.data_delivery_job_runs j where j.singleton and coalesce(j.pim_failed_at, j.pim_measured_at) >= now() - make_interval(mins => v_every)) then\n'
          || E'    declare v_pim jsonb; v_p0 timestamptz := clock_timestamp();\n'
          || E'    begin\n'
          || E'      v_pim := security.pim_progress_v1() || jsonb_build_object(''excluded'', security.pim_excluded_gaps_v1());\n'
          || E'      update pipeline.data_delivery_job_runs set pim = v_pim, pim_measured_at = clock_timestamp(), pim_took_ms = (extract(epoch from clock_timestamp() - v_p0) * 1000)::int,\n'
          || E'             pim_error = null, pim_failed_at = null where singleton;\n'
          || E'    exception when others then\n'
          || E'      update pipeline.data_delivery_job_runs set pim_took_ms = (extract(epoch from clock_timestamp() - v_p0) * 1000)::int, pim_error = left(sqlerrm, 300), pim_failed_at = clock_timestamp() where singleton;\n'
          || E'    end;\n'
          || E'  end if;\n'
          || a;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the refresh anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

-- the screen read: the snapshot, never the count
do $s$
declare d text := pg_get_functiondef('security.data_delivery_v1()'::regprocedure);
        a constant text := E'''pim'', security.pim_progress_v1(),';
        b constant text := E'''pim'', (select coalesce(j.pim, ''{}''::jsonb) || jsonb_build_object(''snapshot_at'', j.pim_measured_at, ''snapshot_ms'', j.pim_took_ms, ''snapshot_error'', j.pim_error, ''snapshot_failed_at'', j.pim_failed_at) from pipeline.data_delivery_job_runs j where j.singleton),';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the pim anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $s$;

-- the first snapshot now, so the screen has figures from the deploy
do $f$
declare v_p0 timestamptz := clock_timestamp(); v_pim jsonb;
begin
  v_pim := security.pim_progress_v1() || jsonb_build_object('excluded', security.pim_excluded_gaps_v1());
  update pipeline.data_delivery_job_runs set pim = v_pim, pim_measured_at = clock_timestamp(), pim_took_ms = (extract(epoch from clock_timestamp() - v_p0) * 1000)::int,
         pim_error = null, pim_failed_at = null where singleton;
end $f$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); x jsonb; v_plan bigint; v_elig bigint; t0 timestamptz; v_ms int;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1167_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1167_cron) then raise exception 'guard: active cron jobs changed'; end if;
  if position('security.pim_progress_v1()' in pg_get_functiondef('security.data_delivery_v1()'::regprocedure)) > 0 then raise exception 'guard: the screen read still runs the count'; end if;
  if position('security.pim_progress_v1()' in pg_get_functiondef('security.data_delivery_refresh_v1(boolean)'::regprocedure)) = 0 then raise exception 'guard: the background count does not run the PIM count'; end if;
  x := (select j.pim from pipeline.data_delivery_job_runs j where j.singleton);
  if x is null or x->'excluded'->'totals' is null or jsonb_array_length(x->'fields') = 0 then raise exception 'guard: the first snapshot is empty'; end if;
  -- the excluded reasons agree with the planner: eligible plus eligible_unconfirmed is what the planner counts
  select coalesce(sum(missing), 0) into v_plan from security.enrich_plan_priority_v1();
  v_elig := coalesce((x->'excluded'->'totals'->>'eligible')::bigint, 0) + coalesce((x->'excluded'->'totals'->>'eligible_unconfirmed')::bigint, 0);
  if v_plan <> v_elig then raise exception 'guard: planner % and eligible reasons % disagree', v_plan, v_elig; end if;
  t0 := clock_timestamp();
  perform security.data_delivery_v1();
  v_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  raise notice 'data delivery read % ms; snapshot % ms', v_ms, (select j.pim_took_ms from pipeline.data_delivery_job_runs j where j.singleton);  -- fixed: milliseconds
end $c$;
