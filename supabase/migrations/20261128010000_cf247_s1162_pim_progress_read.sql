-- CF-247 s1162 (S1-RM-Design; Global Autonomous PIM, F-OPS.21 live progress and queue monitoring; Platform Admin 25 Nov 2026 19:52 and 21:37 AEDT).
-- Production processing progress, in the existing Data Delivery read and no other screen: security.pim_progress_v1() is added to security.data_delivery_v1()
-- (served by public.admin_layer23('data_delivery'), rank 3 and above, unchanged) as one new key, 'pim'. From existing tables only:
--   per country and registered course field: applicable, held (a value is held), backlog (applicable minus held), the work queue by state (queued, running,
--   review, failed, no source found), canonical gains in the window (filled items) and published gains (those for a published provider), throughput per hour,
--   estimated clearance hours (only when throughput is measured, otherwise null and never a guess), the oldest outstanding item;
--   the open source findings (pipeline.course_field_absence) by class; expired leases (still leased past leased_until) and the automatic recovery that takes
--   them back (the lease expiry itself); the scheduled jobs that run the work (schedule, active, next run) and the gap queue's last run;
--   AI use (attempts, failed, cost) and Firecrawl use (calls, credits) in the window; Layer 4 items waiting for a person, by field.
-- The window is the existing data_delivery.net_short_hours setting. No number is written here (G2). Fields with no held-value test report held null (not
-- measured), never 0. Counts for fields the register marks not applicable to a country are not in the applicable figure.
-- The drill-down keys name the existing screens (Scheduled jobs queue and lane control, Operations); the screen wiring belongs to S1-API-Frontend-Delivery.
-- Monitoring acceptance for this slice: it IS the monitoring read; its first screen is the Data Delivery panel's new 'Autonomous PIM' block (UI hand-off in the Master Plan).
-- G1: no job. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: none. Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the guard reads and the first measured run

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if (select md5(pg_get_functiondef('security.data_delivery_v1()'::regprocedure))) <> '1467a69fc8ea311e589af1c2d3be5e6e' then
    raise exception 'guard: security.data_delivery_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1162_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1162_cron on commit drop as select count(*) n from cron.job where active;

create or replace function security.pim_progress_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare v_hours int := greatest(security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int, 1);
        v_since timestamptz; v_fields jsonb; v_abs jsonb; v_jobs jsonb; v_ai jsonb; v_fc jsonb; v_l4 jsonb; v_leases jsonb; v_gap jsonb;
begin
  v_since := now() - make_interval(hours => v_hours);
  with reg as (select r.field, r.absence_field, r.applicability_rule, r.applicability_param from pipeline.field_register r where r.active and r.entity_grain = 'course'),
  c as (
    select co.id course_id, k.iso_alpha2 cc, p.publication_status prov_pub,
           (nullif(btrim(coalesce(co.course_url, '')), '') is not null
              or exists (select 1 from catalogue.course_links l where l.course_id = co.id and l.link_type = 'official_course' and coalesce(l.status, 'active') = 'active')) official_url,
           co.study_level_id is not null level, co.primary_field_id is not null field_of_study, co.duration_value is not null duration,
           nullif(btrim(coalesce(co.delivery_mode, '')), '') is not null delivery,
           exists (select 1 from catalogue.course_campuses x where x.course_id = co.id) campus,
           co.open_to_international is not null international,
           exists (select 1 from catalogue.course_fees f where f.course_id = co.id and f.fee_type ~ '^provider_current_' and coalesce(f.status, 'active') = 'active') provider_tuition,
           exists (select 1 from catalogue.course_fees f where f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and coalesce(f.status, 'active') = 'active') registered_tuition,
           exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active') intakes,
           exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active' and i.application_deadline is not null) deadline,
           exists (select 1 from catalogue.course_english_requirements e where e.course_id = co.id and coalesce(e.status, 'active') = 'active') english,
           exists (select 1 from catalogue.course_entry_requirements q where q.course_id = co.id and q.status = 'active') academic_entry,
           nullif(btrim(coalesce(co.description, '')), '') is not null description
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
     where co.lifecycle_status = 'active'),
  u as (
    select c.cc, c.course_id, c.prov_pub, v.field, v.held, r.absence_field,
           case when r.applicability_rule = 'countries' and not (r.applicability_param->'countries') ? c.cc then false else true end rule_ok
      from c cross join lateral (values ('official_url', c.official_url), ('level', c.level), ('field_of_study', c.field_of_study), ('duration', c.duration),
             ('delivery', c.delivery), ('campus', c.campus), ('international', c.international), ('provider_tuition', c.provider_tuition),
             ('registered_tuition', c.registered_tuition), ('intakes', c.intakes), ('deadline', c.deadline), ('english', c.english),
             ('academic_entry', c.academic_entry), ('description', c.description)) v(field, held)
      join reg r on r.field = v.field),
  ua as (select u.*, not exists (select 1 from pipeline.course_field_absence a where a.course_id = u.course_id and a.field = u.absence_field and a.absence_class = 'not_applicable' and a.resolved_at is null) app_ok from u),
  ap as (select cc, field, count(*) filter (where rule_ok and app_ok) applicable, count(*) filter (where rule_ok and app_ok and held) held,
                count(*) filter (where not (rule_ok and app_ok)) not_applicable
           from ua group by 1, 2),
  q as (
    select k.iso_alpha2 cc, e.field,
           count(*) filter (where e.state in ('queued', 'waiting')) queued,
           count(*) filter (where e.state in ('leased', 'ai') and (e.leased_until is null or e.leased_until >= now())) running,
           count(*) filter (where e.state = 'review') review,
           count(*) filter (where e.state = 'failed') failed,
           count(*) filter (where e.state = 'skipped') no_source_found,
           count(*) filter (where e.state in ('leased', 'ai') and e.leased_until < now()) expired_leases,
           count(*) filter (where e.state = 'filled' and e.updated_at >= v_since) filled_window,
           count(*) filter (where e.state = 'filled' and e.updated_at >= v_since and pr.publication_status = 'published') filled_published_window,
           min(e.created_at) filter (where e.state in ('queued', 'waiting', 'leased', 'ai', 'review')) oldest_outstanding
      from pipeline.field_enrich_items e join catalogue.courses co on co.id = e.course_id join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
     where e.course_id is not null group by 1, 2)
  select coalesce(jsonb_agg(jsonb_build_object(
           'country', ap.cc, 'field', ap.field, 'applicable', ap.applicable, 'not_applicable', ap.not_applicable,
           'held', ap.held, 'backlog', ap.applicable - ap.held,
           'queued', coalesce(q.queued, 0), 'running', coalesce(q.running, 0), 'review', coalesce(q.review, 0), 'failed', coalesce(q.failed, 0), 'no_source_found', coalesce(q.no_source_found, 0),
           'expired_leases', coalesce(q.expired_leases, 0),
           'canonical_gain_window', coalesce(q.filled_window, 0), 'published_gain_window', coalesce(q.filled_published_window, 0),
           'throughput_per_hour', round(coalesce(q.filled_window, 0)::numeric / v_hours, 2),
           'clearance_hours', case when coalesce(q.filled_window, 0) > 0 then round((ap.applicable - ap.held)::numeric / (q.filled_window::numeric / v_hours), 1) end,
           'oldest_outstanding', q.oldest_outstanding) order by ap.cc, ap.field), '[]'::jsonb)
    into v_fields from ap left join q on q.cc = ap.cc and q.field = ap.field;
  select coalesce(jsonb_agg(z order by z->>'country', z->>'class'), '[]'::jsonb) into v_abs
    from (select jsonb_build_object('country', k.iso_alpha2, 'class', a.absence_class, 'open', count(*)) z
            from pipeline.course_field_absence a join catalogue.courses co on co.id = a.course_id join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
           where a.resolved_at is null group by k.iso_alpha2, a.absence_class) s;
  select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'active', j.active, 'schedule', j.schedule,
           'next_run', case when j.active then security.cron_next_run_v1(j.schedule, now()) end) order by j.jobname), '[]'::jsonb)
    into v_jobs from cron.job j where j.jobname in ('enrich-plan-run', 'enrich-plan-auto', 'field-gap-queue');
  select jsonb_build_object('cycle', k.cycle, 'last_run_at', k.last_run_at, 'cycle_started_at', k.cycle_started_at, 'cycle_scanned', k.cycle_scanned, 'cycle_found', k.cycle_found)
    into v_gap from pipeline.field_gap_queue_checkpoint k where k.id = 1;
  select jsonb_build_object('attempts', count(*), 'failed', count(*) filter (where i.outcome = 'failed'), 'cost_usd', coalesce(round(sum(i.cost_usd)::numeric, 4), 0))
    into v_ai from pipeline.ai_invocations i where i.at >= v_since;
  select jsonb_build_object('calls', count(*), 'credits', coalesce(sum(f.credits_used), 0)) into v_fc from pipeline.firecrawl_calls f where f.at >= v_since;
  select coalesce(jsonb_agg(jsonb_build_object('field', s.field_code, 'waiting', s.n, 'oldest', s.oldest) order by s.n desc), '[]'::jsonb)
    into v_l4 from (select i.field_code, count(*) n, min(i.created_at) oldest from pipeline.layer4_review_items i where i.status = 'pending' group by 1) s;
  select jsonb_build_object('expired', count(*), 'recovery', 'A lease past its time is taken back by the next worker claim; nothing is restored by hand.')
    into v_leases from pipeline.field_enrich_items e where e.state in ('leased', 'ai') and e.leased_until < now();
  return jsonb_build_object('as_at', now(), 'window_hours', v_hours, 'fields', v_fields, 'source_findings', v_abs, 'jobs', v_jobs, 'gap_queue', v_gap,
    'ai', v_ai, 'firecrawl', v_fc, 'human_required', jsonb_build_object('layer4_waiting', v_l4, 'enrich_review', (select count(*) from pipeline.field_enrich_items e where e.state = 'review')),
    'leases', v_leases,
    'drill', jsonb_build_object('queues_and_lanes', 'Scheduled jobs › Queue & lane control', 'operations', 'Layer 2/3 Build & enrich › Operations', 'layer4', 'Layer 4 Review'),
    'meaning', jsonb_build_object('applicable', 'fields the register says apply; an undefined rule is never counted as applicable',
      'clearance_hours', 'backlog divided by the measured hourly gain in the window; null when nothing was gained, never a guess',
      'published_gain', 'canonical gains for courses of a published provider'));
end $f$;
comment on function security.pim_progress_v1() is 'PIM monitoring (s1162, F-OPS.21): production processing progress by country and course field, from existing tables; read through security.data_delivery_v1 key pim.';
revoke all on function security.pim_progress_v1() from public, anon, authenticated;
grant execute on function security.pim_progress_v1() to service_role;

-- the one new key in the existing Data Delivery read: the live definition with 'pim' added after 'streams' (checked above to be the definition this change was written against)
do $r$
declare d text := pg_get_functiondef('security.data_delivery_v1()'::regprocedure);
begin
  if (length(d) - length(replace(d, E'''streams'', v_out,', ''))) / length(E'''streams'', v_out,') <> 1 then raise exception 'guard: the streams anchor is not found exactly once'; end if;
  d := replace(d, E'''streams'', v_out,', E'''streams'', v_out, ''pim'', security.pim_progress_v1(),');
  execute d;
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); p jsonb; t0 timestamptz := clock_timestamp(); d jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1162_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1162_cron) then raise exception 'guard: active cron jobs changed'; end if;
  p := security.pim_progress_v1();
  if jsonb_array_length(p->'fields') < 20 then raise exception 'guard: fewer than 20 country and field rows: %', jsonb_array_length(p->'fields'); end if;  -- fixed: three countries and the registered course fields
  if exists (select 1 from jsonb_array_elements(p->'fields') f where (f->>'applicable')::int < (f->>'held')::int) then raise exception 'guard: held exceeds applicable'; end if;
  if exists (select 1 from jsonb_array_elements(p->'fields') f where f->>'field' = 'registered_tuition' and f->>'country' <> 'AU' and (f->>'applicable')::int <> 0) then raise exception 'guard: registered tuition applicable outside AU'; end if;
  d := security.data_delivery_v1();
  if d->'pim' is null or d->'streams' is null then raise exception 'guard: data_delivery_v1 lacks pim or streams'; end if;
  raise notice 'pim_progress_v1 read in % ms; % rows', (extract(epoch from clock_timestamp() - t0) * 1000)::int, jsonb_array_length(p->'fields');  -- fixed: milliseconds
end $c$;
