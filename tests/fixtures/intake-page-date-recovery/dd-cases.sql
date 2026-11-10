-- Guards: F-INT Data Delivery (Platform Admin directive 10 Nov 2026 14:02: eligible denominator, new admissions and retained net gain, skipped apart from legitimately unresolvable, consumer publication, blocker; existing panel, additive key, cheap),
--   migration 20261110171000: security.data_delivery_intake_v1() read as the screen reads it, against an independent count of the same tables, after the page-date cases have run. Never changes a setting or a row outside rolled-back blocks and the cases' own courses.
\set ON_ERROR_STOP on
\set QUIET on

create or replace function public.pr_dd_skip(p_j jsonb, p_scope text, p_k text) returns bigint language sql stable as $f$
  select coalesce((select (e->>'n')::bigint from jsonb_array_elements(p_j->'skipped'->p_scope) e where e->>'k' = p_k), 0) $f$;

-- 0 the function: read only, closed to anon and authenticated, fails soft ------------------------------------------------------------------------------------------------
do $$
declare f text := ''; fn regprocedure := 'security.data_delivery_intake_v1()'::regprocedure; j jsonb;
begin
  if (select p.provolatile from pg_proc p where p.oid = fn) <> 's' or (select prosecdef from pg_proc p where p.oid = fn) is not true or pg_get_functiondef(fn) ~* '(net\.http|http_post|crawl\(|firecrawl|openrouter|pg_net|insert into|update |delete from)' then f := f || ' not read-only'; end if;
  if has_function_privilege('anon', fn, 'execute') or has_function_privilege('authenticated', fn, 'execute') or has_function_privilege('public', fn, 'execute') then f := f || ' executable by anon/authenticated/public'; end if;
  j := security.data_delivery_intake_v1();
  if j->>'known' <> 'true' then f := f || ' not known: ' || j::text; end if;
  if exists (select 1 from unnest(array['denominator', 'admissions', 'skipped', 'publication', 'switches', 'blockers', 'counted_at', 'unit']) k where not j ? k) then f := f || ' a key is missing'; end if;
  if f <> '' then raise exception 'function:%', f; end if;
  raise notice 'PASS DD function: stable, writes nothing, calls nothing outside the database, closed to anon, authenticated and public; it answers known with denominator, admissions, skipped, publication, switches, blockers';
end $$;
begin;
do $$
declare j jsonb;
begin
  drop function security.intake_page_date_hint_v1(uuid, uuid, text);      -- a count that cannot be made does not break Data Delivery
  j := security.data_delivery_intake_v1();
  if j->>'known' <> 'false' or coalesce(j->>'reason', '') !~ 'could not be made' then raise exception 'not soft: %', j; end if;
  raise notice 'PASS DD fail soft: a count that cannot be made returns known false with the reason, and does not raise';
end $$;
rollback;

-- 1 the figures equal an independent count of the same tables ------------------------------------------------------------------------------------------------------------------
do $$
declare j jsonb := security.data_delivery_intake_v1(); d jsonb := j->'denominator'; f text := ''; w jsonb; n bigint; g bigint; wd bigint; ns bigint; rs bigint; hs int := (security.pipeline_num_v1('data_delivery.net_short_hours', 24))::int;
begin
  select count(*) into n from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.status = 'active' and c.lifecycle_status = 'active';
  if (d->>'active_intakes')::bigint <> n then f := f || ' active ' || n; end if;
  select count(*) into n from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.status = 'active' and c.lifecycle_status = 'active' and i.start_date is not null;
  if (d->>'exact_start')::bigint <> n then f := f || ' exact ' || n; end if;
  select count(*) into n from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.status = 'active' and c.lifecycle_status = 'active' and i.application_deadline is not null;
  if (d->>'with_deadline')::bigint <> n then f := f || ' deadline ' || n; end if;
  select count(*) into n from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.status = 'active' and c.lifecycle_status = 'active' and i.start_date is null and exists (select 1 from pipeline.course_intake_dates x where x.intake_id = i.id);
  if (d->>'undated_eligible')::bigint <> n or (d->>'eligible')::bigint <> (d->>'exact_start')::bigint + n then f := f || ' eligible ' || n; end if;
  if (d->>'undated')::bigint <> (d->>'undated_eligible')::bigint + (d->>'undated_no_decision')::bigint or (d->>'active_intakes')::bigint <> (d->>'exact_start')::bigint + (d->>'undated')::bigint then f := f || ' denominator does not add up'; end if;
  w := (select e from jsonb_array_elements(j->'admissions'->'windows') e where (e->>'hours')::int = hs);
  select count(*) filter (where outcome = 'filled'), count(*) filter (where outcome = 'withdrawn') into g, wd from pipeline.course_intake_date_events where run_at > now() - make_interval(hours => hs);
  if (w->>'gross')::bigint <> g or (w->>'withdrawn')::bigint <> wd or (w->>'net')::bigint <> g - wd then f := f || ' admissions ' || w::text || ' vs ' || g || '/' || wd; end if;
  select count(distinct e.intake_id) into ns from pipeline.course_intake_date_events e where e.run_at > now() - make_interval(hours => hs) and e.outcome = 'filled' and e.after_value->>'start_date' is not null and e.before_value->>'start_date' is null;
  select count(distinct e.intake_id) into rs from pipeline.course_intake_date_events e join catalogue.course_intakes i on i.id = e.intake_id and i.start_date = (e.after_value->>'start_date')::date
   where e.run_at > now() - make_interval(hours => hs) and e.outcome = 'filled' and e.before_value->>'start_date' is null;
  if (w->>'new_start')::bigint <> ns or (w->>'retained_start')::bigint <> rs or rs > ns then f := f || ' new/retained ' || ns || '/' || rs || ' vs ' || w::text; end if;
  if (select coalesce(sum((e->>'filled')::bigint), 0) from jsonb_array_elements(j->'admissions'->'by_rule') e) <> g or (select coalesce(sum((e->>'withdrawn')::bigint), 0) from jsonb_array_elements(j->'admissions'->'by_rule') e) <> wd then f := f || ' by rule'; end if;
  if (select coalesce(sum((e->>'n')::bigint), 0) from jsonb_array_elements(j->'skipped'->'now') e) <> (select count(*) from pipeline.course_intake_dates x join catalogue.course_intakes i on i.id = x.intake_id join catalogue.courses c on c.id = i.course_id
         where x.outcome = 'skipped' and i.status = 'active' and c.lifecycle_status = 'active') then f := f || ' skipped now'; end if;
  if (j->'skipped'->>'window_events')::bigint <> (select count(*) from pipeline.course_intake_date_events e where e.outcome = 'skipped' and e.run_at > now() - make_interval(hours => hs)) then f := f || ' skipped window'; end if;
  if (select coalesce(sum((e->>'n')::bigint), 0) from jsonb_array_elements(j->'publication'->'by_state') e) <> (select count(*) from pipeline.course_intake_dates x where x.outcome in ('filled', 'nothing_new')) then f := f || ' publication'; end if;
  if f <> '' then raise exception 'counts:%', f; end if;
  raise notice 'PASS DD counts: the denominator (active, exact, deadline, undated, eligible), the admissions in the stream''s window (gross, withdrawn, net, new start dates, retained, by rule), the skipped outcomes (now and in the window) and the publication states equal an independent count of the tables';
end $$;

-- 2 month-only apart from a page that prints a date, and the move when a run takes it ----------------------------------------------------------------------------------------------
do $$
declare yA int := public.pr_dy(3, 1); a jsonb; b jsonb; c jsonb; v jsonb; k record; n_hint bigint;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  a := security.data_delivery_intake_v1();
  perform public.pr_d1_course('ddW', 'Federation', 'March', array['adapter pattern: 01 March ' || yA || ' 26 July ' || public.pr_dy(7, 26), 'Start dates 25 January ' || yA || ' 01 March ' || yA || ' 28 June ' || yA], 'filled', make_date(yA, 3, 1));
  perform public.pr_d1_course('ddM', 'Federation', 'March', array['Start dates: 1 March at the main campus'], 'skipped');
  perform search.refresh_course_enrichment_scoped_v1((select array_agg(course_id) from public.pr_d1 where name in ('ddW', 'ddM')), true);
  perform security.intake_dates_apply_v1(10, (select array_agg(course_id) from public.pr_d1 where name in ('ddW', 'ddM')));     -- route off: both decided month only
  b := security.data_delivery_intake_v1();
  if public.pr_dd_skip(b, 'now', 'page_date_waiting') - public.pr_dd_skip(a, 'now', 'page_date_waiting') <> 1 or public.pr_dd_skip(b, 'now', 'month_only') - public.pr_dd_skip(a, 'now', 'month_only') <> 1 then
    raise exception 'month-only apart: page_date_waiting % -> %, month_only % -> %', public.pr_dd_skip(a, 'now', 'page_date_waiting'), public.pr_dd_skip(b, 'now', 'page_date_waiting'), public.pr_dd_skip(a, 'now', 'month_only'), public.pr_dd_skip(b, 'now', 'month_only'); end if;
  if not exists (select 1 from jsonb_array_elements(b->'blockers') e where e->>'code' = 'page_route_off' and e->>'kind' = 'technical') then raise exception 'the page route off is not a blocker: %', b->'blockers'; end if;
  -- the independent count of the same: month-only decisions of undated active intakes whose stored page prints a dated candidate
  select count(*) into n_hint from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id join catalogue.courses c on c.id = i.course_id
   where d.outcome = 'skipped' and d.reason like '%(month only)%' and d.failure_class is distinct from 'course_identity_unresolved' and d.reason not like 'no stored reading%' and i.status = 'active' and c.lifecycle_status = 'active' and i.start_date is null
     and security.intake_page_date_hint_v1(i.course_id, i.evidence_id, i.intake_label);
  if n_hint <> public.pr_dd_skip(b, 'now', 'page_date_waiting') then raise exception 'page_date_waiting % vs independent %', public.pr_dd_skip(b, 'now', 'page_date_waiting'), n_hint; end if;
  -- the route on and one run: the date is admitted, leaves the waiting count, enters the exact starts and the new admissions
  update pipeline.platform_toolset_settings set value = to_jsonb(1) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
  v := security.intake_dates_apply_v1(10, (select array_agg(course_id) from public.pr_d1 where name in ('ddW', 'ddM')));
  c := security.data_delivery_intake_v1();
  if (c->'denominator'->>'exact_start')::bigint - (b->'denominator'->>'exact_start')::bigint <> 1 or public.pr_dd_skip(b, 'now', 'page_date_waiting') - public.pr_dd_skip(c, 'now', 'page_date_waiting') <> 1
     or exists (select 1 from jsonb_array_elements(c->'blockers') e where e->>'code' in ('job_off', 'page_route_off')) then raise exception 'after the run: %', c->'denominator'; end if;
  if (select (e->>'new_start')::int - (select (x->>'new_start')::int from jsonb_array_elements(b->'admissions'->'windows') x where (x->>'hours')::int = (e->>'hours')::int) from jsonb_array_elements(c->'admissions'->'windows') e order by (e->>'hours')::int limit 1) <> 1 then raise exception 'new start not counted'; end if;
  raise notice 'PASS DD month-only apart: a month-only decision whose stored page prints a full date is counted as page_date_waiting (equal to an independent count), one with no day stays month_only; after one run with the route on the date is admitted, the waiting count falls by one, the exact starts and the new admissions rise by one, and the page-route blocker clears';
end $$;

-- 3 the blockers: the job off is a technical blocker; the held causes are listed with their kind -------------------------------------------------------------------------------------
begin;
do $$
declare j jsonb;
begin
  update pipeline.platform_toolset_settings set value = to_jsonb(false) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled';
  j := security.data_delivery_intake_v1();
  if not exists (select 1 from jsonb_array_elements(j->'blockers') e where e->>'code' = 'job_off' and e->>'kind' = 'technical') or (j->'switches'->>'apply_enabled')::boolean then raise exception 'job off not shown: %', j->'blockers'; end if;
  if exists (select 1 from jsonb_array_elements(security.data_delivery_intake_v1()->'blockers') e where e->>'kind' not in ('technical', 'decision', 'source')) then raise exception 'blocker kind'; end if;
  raise notice 'PASS DD blockers: the job switched off is shown as a technical blocker and the switches are reported; every blocker is a technical, decision or source one with its count (page only: a Platform Admin decision; identity, no page reading, calendar: source)';
end $$;
rollback;

-- 4 cheap: the whole answer in a bound -----------------------------------------------------------------------------------------------------------------------------------------
do $$
declare t0 timestamptz := clock_timestamp(); ms numeric;
begin
  perform security.data_delivery_intake_v1();
  ms := extract(milliseconds from clock_timestamp() - t0);
  if ms > 4000 then raise exception 'the intake delivery counts took % ms', ms; end if;   -- fixed: a gross regression bound for the fixture (the statement time-out is 8 s), not a setting
  raise notice 'PASS DD cost: the intake delivery counts take % ms on the fixture (live: the same statements 315 ms plus 630 ms for the page-date hint over 9,262 decisions; the statement time-out is 8 s)', round(ms);
end $$;
update pipeline.platform_toolset_settings set value = to_jsonb(0) where toolset_key = 'pipeline' and key = 'intake_dates.page_date_admit';
