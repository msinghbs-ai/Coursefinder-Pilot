-- Guards: CF-247 Operations load speed (Platform Admin P1, 10 Nov 2026): the live definitions the migration edits, exactly as production holds them (pg_get_functiondef, project fxcwkweaxjtknorudmwp, read 10 Nov 2026 AEDT).
-- Loaded with check_function_bodies off (the tables they read are the stubs of schema-extra.sql). The body md5 of each is asserted by run.sh.

CREATE OR REPLACE FUNCTION security.intake_progress_repeats_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- Platform Admin 5 Nov 2026 22:46: each deterministic refusal of the last day that repeats the same failure class of the same intake row is classified
  -- from existing records only, in this order:
  --   excluded_source_update   the calendar set, calendar document, approved reading, periods, evidence year or course page wording differ between the two decisions;
  --   excluded_reader_revision the reader or rule differ, or a release that changed an intake or calendar function was deployed between them
  --                            (pipeline.integration_deploy_checks.result->functions);
  --   excluded_setting_change  an intake_dates.* or run_now.* setting was changed between them: the Settings audit (pipeline.admin_control_events)
  --                            or, for a change written without an audit row, the setting's last-changed time (platform_toolset_settings.updated_at);
  --   unverified_repeat        the inputs of the later decision cannot be established and the earlier one shows no difference (no calendar set, page
  --                            wording or rule on both), or a release between them does not record the functions it changed; a gap on only one
  --                            of the two decisions is a difference and counts as a source update (also never raised);
  --   confirmed                otherwise: evidence, reader and settings demonstrably unchanged.
  with ev as (select e.intake_id, e.run_at, e.failure_class, e.calendar_set, e.calendar_evidence_id, e.proposal_id, e.periods, e.evidence_year, e.page_quote, e.reader, e.rule,
                     p.run_at p_at, p.calendar_set p_set, p.calendar_evidence_id p_doc, p.proposal_id p_prop, p.periods p_periods, p.evidence_year p_year, p.page_quote p_quote,
                     p.reader p_reader, p.rule p_rule, p.next_revisit_at p_revisit
                from pipeline.course_intake_date_events e
                cross join lateral (select x.* from pipeline.course_intake_date_events x
                                     where x.intake_id = e.intake_id and x.run_at < e.run_at and x.failure_class = e.failure_class order by x.run_at desc limit 1) p
               where e.run_at >= now() - make_interval(days => 1) and e.deterministic and e.outcome = 'skipped'),  -- fixed: the one-day check named by decision 16:36 §6
  st as (select a.created_at at from pipeline.admin_control_events a
          where a.area in ('toolsets', 'settings') and a.action in ('setting', 'change') and a.target ~ '^(pipeline\.)?(intake_dates|run_now)\.'
            and a.created_at >= (select min(ev.p_at) from ev)
         -- a change written without an audit row (for example by a release) is still seen through the setting's own last-changed time
         union all
         select s.updated_at from pipeline.platform_toolset_settings s
          where s.toolset_key = 'pipeline' and s.key ~ '^(intake_dates|run_now)\.' and s.updated_at >= (select min(ev.p_at) from ev)),
  rel as (select r.since at, exists (select 1 from jsonb_array_elements(case when jsonb_typeof(r.result->'functions') = 'array' then r.result->'functions' else '[]'::jsonb end) f
                                      where f->>'function' ~ '^security\.(intake_|calendar_)') intake_fn,
                 coalesce(jsonb_typeof(r.result->'functions') = 'array', false) known
            from pipeline.integration_deploy_checks r where r.since >= (select min(ev.p_at) from ev)),
  k as (select ev.*, case
          when ev.calendar_set is distinct from ev.p_set or ev.calendar_evidence_id is distinct from ev.p_doc or ev.proposal_id is distinct from ev.p_prop
               or ev.periods is distinct from ev.p_periods or ev.evidence_year is distinct from ev.p_year or ev.page_quote is distinct from ev.p_quote then 'excluded_source_update'
          when ev.reader is distinct from ev.p_reader or ev.rule is distinct from ev.p_rule
               or exists (select 1 from rel where rel.at > ev.p_at and rel.at < ev.run_at and rel.intake_fn) then 'excluded_reader_revision'
          when exists (select 1 from st where st.at > ev.p_at and st.at < ev.run_at) then 'excluded_setting_change'
          -- F-INT 9 Nov 2026: the earlier decision set a revisit time and this look is on or after it: a scheduled look, not an unchanged repeat
          when ev.p_revisit is not null and ev.run_at >= ev.p_revisit then 'excluded_scheduled_revisit'
          when ev.calendar_set is null or ev.page_quote is null or ev.rule is null
               or exists (select 1 from rel where rel.at > ev.p_at and rel.at < ev.run_at and not rel.known) then 'unverified_repeat'
          else 'confirmed' end status from ev)
  select jsonb_build_object(
    'confirmed', (select count(distinct k.intake_id) from k where k.status = 'confirmed'),
    'excluded_source_update', (select count(distinct k.intake_id) from k where k.status = 'excluded_source_update'),
    'excluded_reader_revision', (select count(distinct k.intake_id) from k where k.status = 'excluded_reader_revision'),
    'excluded_setting_change', (select count(distinct k.intake_id) from k where k.status = 'excluded_setting_change'),
    'excluded_scheduled_revisit', (select count(distinct k.intake_id) from k where k.status = 'excluded_scheduled_revisit'),
    'unverified_repeat', (select count(distinct k.intake_id) from k where k.status = 'unverified_repeat'),
    'examples', (select coalesce(jsonb_agg(jsonb_build_object('status', z.status, 'intake_id', z.intake_id, 'class', z.failure_class, 'decided', z.run_at, 'earlier', z.p_at)), '[]'::jsonb)
                   from (select distinct on (k.status) k.* from k order by k.status, k.run_at desc) z))
$function$;

CREATE OR REPLACE FUNCTION security.process_results_recovery_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with u as (select (e->>'id')::uuid id, e->>'name' name from jsonb_array_elements(security.intake_ui_scopes_v1()) e),
  w as (select now() - make_interval(days => security.pipeline_num_v1('process_results.window_days', 7)::int) since),
  ev as (select e.* from pipeline.course_intake_date_events e, w where e.run_at >= w.since and e.provider_id in (select id from u)),
  d as (select d.* from pipeline.course_intake_dates d where d.provider_id in (select id from u))
  select jsonb_build_object(
    'measured_at', now(), 'window_since', (select since from w),
    'admitted', (select coalesce(jsonb_agg(x order by x->>'university', x->>'year'), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'source_type', 'approved calendar', 'rule', ev.rule, 'year', coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int),
                'precision', ev.start_precision, 'admitted', count(*), 'with_start_date', count(*) filter (where ev.after_value->>'start_date' is not null),
                'with_deadline', count(*) filter (where ev.after_value->>'application_deadline' is not null),
                'published', count(*) filter (where ev.publication_state = 'published'), 'publication_failed', count(*) filter (where ev.publication_state = 'consumer_publication_failed'),
                'provider_not_published', count(*) filter (where ev.publication_state in ('provider_not_published', 'course_not_in_consumer_source')), 'not_checked', count(*) filter (where ev.publication_state is null)) x
         from ev join u on u.id = ev.provider_id where ev.outcome = 'filled'
        group by u.name, ev.rule, coalesce((ev.after_value->>'year')::int, (ev.before_value->>'year')::int), ev.start_precision) z),
    'classes', (select coalesce(jsonb_agg(x order by (x->>'rows')::int desc), '[]'::jsonb) from (
       select jsonb_build_object('university', u.name, 'class', coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end),
                'deterministic', bool_and(d.deterministic), 'rows', count(*), 'reason', min(d.reason), 'next_revisit_at', min(d.next_revisit_at), 'revisit_trigger', min(d.revisit_trigger)) x
         from d join u on u.id = d.provider_id
        group by u.name, coalesce(d.failure_class, case when d.next_action = 'complete' then 'complete' else 'not_classified_yet' end)) z),
    'refresh', jsonb_build_object(
       'budget', security.pipeline_num_v1('central.calendar_refresh_credit_budget', 40),
       'credits_counted', (select coalesce(sum(greatest(q.credit_estimate, coalesce(q.credits_used, 0))), 0) from pipeline.calendar_refresh_requests q),
       'credits_used', (select coalesce(sum(q.credits_used), 0) from pipeline.calendar_refresh_requests q),
       'requests', (select coalesce(jsonb_agg(jsonb_build_object('university', u.name, 'url', q.url, 'requested_at', q.requested_at, 'reason', q.reason, 'status', q.status,
                       'credits_used', q.credits_used, 'yield', q.yield, 'next_year_starts', q.next_year_starts) order by q.requested_at desc), '[]'::jsonb)
                      from pipeline.calendar_refresh_requests q join u on u.id = q.provider_id)),
    'reader', (select coalesce(jsonb_agg(jsonb_build_object('reader', s.reader_version, 'state', s.state, 'documents', s.n) order by s.reader_version nulls first, s.state), '[]'::jsonb)
                 from (select reader_version, state, count(*) n from pipeline.calendar_reread_state group by 1, 2) s),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'last_run', (select max(r.start_time) from cron.job_run_details r where r.jobid = j.jobid),
                       'last_status', (select r.status from cron.job_run_details r where r.jobid = j.jobid order by r.start_time desc limit 1))), '[]'::jsonb)
               from cron.job j where j.jobname in ('calendar-reread', 'central-ai', 'provider-facts', 'intake-dates-apply', 'process-results')))
$function$;

CREATE OR REPLACE FUNCTION public.admin_layer23(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int; v_out jsonb; v_list jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  v_rank := security.current_role_rank();
  if coalesce(v_rank, 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_action = 'data_delivery' then
    -- CF-247 F-OPS.03A (Platform Admin 9 Nov 2026): the Data Delivery summary at the top of Layer 2/3 > Operations. One read, same rank as the screen (3 and above, checked above).
    return security.data_delivery_v1();
  end if;
  if p_action = 'universities_page' then
    -- CF-247 W33 (30 Oct 2026): one page of Layer 2/3 › Universities. The filters, the name search and the order (by name) the screen
    -- offered on the whole list are applied here; the page size and the most rows ticked at once are settings (layer23.*). The same
    -- rows and fields as 'universities'; the onboarding stage and the course-page counts are worked out for the rows of the page only.
    -- mode 'ticks' answers every matching row in short form (for Tick every row shown), and no page.
    declare
      v_size int := greatest(security.pipeline_num_v1('layer23.universities_page_size', 100)::int, 1);
      v_tick_max int := greatest(security.pipeline_num_v1('layer23.universities_tick_max', 2000)::int, 1);
      v_off int := greatest(coalesce(nullif(p_args->>'offset', '')::int, 0), 0);
      v_ticks boolean := coalesce(p_args->>'mode', '') = 'ticks';
      v_pid uuid := nullif(p_args->>'provider_id', '')::uuid;
      v_country text := nullif(btrim(coalesce(p_args->>'country', '')), '');
      v_state text := nullif(btrim(coalesce(p_args->>'state', '')), '');
      v_kind text := coalesce(nullif(btrim(coalesce(p_args->>'kind', '')), ''), 'any');
      v_adapter text := nullif(btrim(coalesce(p_args->>'adapter', '')), '');
      v_qualify text := nullif(btrim(coalesce(p_args->>'qualify', '')), '');
      v_target text := nullif(btrim(coalesce(p_args->>'target', '')), '');
      v_stage text := nullif(btrim(coalesce(p_args->>'stage', '')), '');
      v_q text := nullif(btrim(coalesce(p_args->>'q', '')), '');
      v_pat text := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
      -- the read-cycle bounds are those public.admin_adapters enforces in set_cycle and answers in 'list' (kept identical to it)
      v_settings jsonb := case when v_rank >= 4 then jsonb_build_object('read_cycle_default', 90, 'read_cycle_min', 7, 'read_cycle_max', 365,
                            'min_read_share', coalesce(security.firecrawl_setting('eval_field_share'), '0.5'::jsonb),
                            'min_agree_share', coalesce(security.firecrawl_setting('qualify_agree_share'), '0.9'::jsonb)) end;
    begin
        with t as materialized (select x.provider_id, x.included, x.rule_match, x.override_reason from security.firecrawl_targets_fast() x where v_rank >= 4),
        ob as materialized (select distinct on (o.provider_id) o.id, o.provider_id, o.status, o.stop_reason, o.note, o.result, o.updated_at
                              from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc),
        ib as materialized (select i.provider_id, i.kind, count(*) c from security.layer4_inbox_items_v1() i where i.provider_id is not null group by 1, 2),
        ibn as (select ib.provider_id, sum(ib.c)::int n from ib group by 1),
        q as (select distinct on (x.provider_id) x.provider_id, x.job_id, x.measured_at, x.passing, x.pages_read
                from pipeline.adapter_qualifications x join pipeline.admin_jobs j on j.id = x.job_id and j.kind = 'qualify_adapters' and j.state = 'done'
               where v_rank >= 4 order by x.provider_id, x.measured_at desc),
        ids as (select a.provider_id from pipeline.uni_adapters a where v_rank >= 4 union select t.provider_id from t where t.included union select ob.provider_id from ob),
        u as materialized (
          select p.id provider_id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2 country, s.code state, l.inlist,
                 case when l.inlist then coalesce(p.display_name, p.canonical_name) ~* v_pat else true end university,
                 case when l.inlist and a.provider_id is not null then case when not a.enabled then 'off' when a.admit then 'admitting' else 'testing' end end adapter_state,
                 case when l.inlist and a.admit then coalesce(a.admit_fields, '{}') else '{}' end admit_fields,
                 l.inlist and q.provider_id is not null qualified, case when l.inlist then coalesce(q.passing, '{}') else '{}' end passing,
                 case when l.inlist then t.included end target_included,
                 ob.id ob_id, ob.status ob_status, ob.stop_reason ob_stop, coalesce(ibn.n, 0) inbox
            from ids join catalogue.providers p on p.id = ids.provider_id
            left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
            left join pipeline.uni_adapters a on a.provider_id = p.id and v_rank >= 4
            left join t on t.provider_id = p.id left join q on q.provider_id = p.id
            left join ob on ob.provider_id = p.id left join ibn on ibn.provider_id = p.id
            cross join lateral (select v_rank >= 4 and (a.provider_id is not null or coalesce(t.included, false)) inlist) l),
        f as materialized (
          select u.* from u
           where (v_pid is null or u.provider_id = v_pid)
             and (v_country is null or u.country = v_country) and (v_state is null or u.state = v_state)
             and (v_kind <> 'university' or u.university)
             and (v_adapter is null or (v_adapter = 'none' and u.adapter_state is null) or u.adapter_state = v_adapter)
             and (v_qualify is null
                  or (v_qualify = 'never' and not u.qualified)
                  or (v_qualify = 'passing' and cardinality(u.passing) > 0)
                  or (v_qualify = 'waiting' and u.adapter_state is not null and u.adapter_state <> 'off' and exists (select 1 from unnest(u.passing) x where x <> all (u.admit_fields)))
                  or (v_qualify not in ('never', 'passing', 'waiting') and u.qualified and cardinality(u.passing) = 0))
             and (v_target is null or (v_target = 'in' and coalesce(u.target_included, false)) or (v_target <> 'in' and not coalesce(u.target_included, false)))
             and (v_q is null or strpos(lower(u.name), lower(v_q)) > 0)
             and (v_stage is null
                  or (v_stage = 'none' and u.ob_id is null)
                  or (v_stage = 'inbox' and u.inbox > 0)
                  or (u.ob_id is not null and (
                       (v_stage = 'working' and u.ob_status in ('queued', 'website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying', 'scholarships', 'waiting_admit', 'waiting_courses'))
                    or (v_stage = 'person' and u.ob_status = 'stopped' and coalesce(u.ob_stop, '') in ('nothing_ready', 'approve_central'))
                    or (v_stage = 'stopped' and u.ob_status = 'stopped' and coalesce(u.ob_stop, '') not in ('nothing_ready', 'approve_central'))
                    or (v_stage = 'done' and u.ob_status = 'done')
                    or v_stage not in ('none', 'inbox', 'working', 'person', 'stopped', 'done'))))),
        pg as (select f.* from f order by f.name, f.provider_id offset v_off limit v_size)
        select jsonb_build_object('as_at', now(), 'can_manage', v_rank >= 6, 'can_qualify', v_rank >= 5, 'can_onboard', v_rank >= 6, 'settings', v_settings,
          'paged', true, 'page_size', v_size, 'offset', v_off,
          'total', (select count(*) from u), 'matched', (select count(*) from f),
          'tally', (select jsonb_build_object('admitting', count(*) filter (where f.adapter_state = 'admitting'), 'testing', count(*) filter (where f.adapter_state = 'testing'),
                                              'off', count(*) filter (where f.adapter_state = 'off'), 'none', count(*) filter (where f.adapter_state is null)) from f),
          'countries', (select coalesce(jsonb_agg(z.c order by z.c collate "C"), '[]'::jsonb) from (select distinct u.country c from u where u.country is not null) z),
          'states', (select coalesce(jsonb_agg(z.c order by z.c collate "C"), '[]'::jsonb) from (select distinct u.state c from u where u.state is not null and (v_country is null or u.country = v_country)) z),
          'adapters', case when v_ticks then '[]'::jsonb else (select coalesce(jsonb_agg(jsonb_build_object(
              'provider_id', pg.provider_id, 'name', pg.name, 'country', pg.country, 'state', pg.state, 'university', pg.university,
              'adapter', case when pg.adapter_state is null then null else jsonb_build_object('state', pg.adapter_state, 'fields', to_jsonb(pg.admit_fields), 'read_cycle_days', a.read_cycle_days, 'updated_at', a.updated_at, 'admit_changed_at', a.admit_changed_at) end,
              'target', case when pg.target_included is null then null else jsonb_build_object('included', t.included, 'rule_match', t.rule_match, 'override_reason', t.override_reason,
                             'rule_reason', (select c.rule_reason from pipeline.firecrawl_target_cache c where c.provider_id = pg.provider_id)) end,
              'pages', gp.pages, 'pages_read', gp.pages_read, 'next_read', gp.next_read, 'last_read', gp.last_read,
              'qualify', case when not pg.qualified then null else jsonb_build_object('job_id', q.job_id, 'at', q.measured_at, 'passing', to_jsonb(q.passing), 'pages_read', q.pages_read) end,
              'onboarding', case when pg.ob_id is null then null else jsonb_build_object('id', ob.id, 'status', ob.status, 'stage', security.provider_onboarding_stage_v1(ob.status, ob.stop_reason, ob.result),
                             'phase', ob.result->>'phase', 'stop_reason', ob.stop_reason, 'note', ob.note, 'updated_at', ob.updated_at) end,
              'inbox', pg.inbox, 'inbox_kinds', coalesce((select jsonb_object_agg(ib.kind, ib.c) from ib where ib.provider_id = pg.provider_id), '{}'::jsonb))
              order by pg.name, pg.provider_id), '[]'::jsonb)
            from pg left join pipeline.uni_adapters a on a.provider_id = pg.provider_id left join t on t.provider_id = pg.provider_id
            left join q on q.provider_id = pg.provider_id left join ob on ob.provider_id = pg.provider_id
            cross join lateral (select count(*) pages, count(*) filter (where g.read_status = 'read') pages_read,
                                       min(g.next_read_at) filter (where g.read_status in ('read', 'identity_mismatch')) next_read, max(g.read_at) last_read
                                  from pipeline.coverage_course_pages g where g.provider_id = pg.provider_id) gp) end,
          'ticks', case when not v_ticks then null else (select jsonb_build_object('capped', count(*) > v_tick_max, 'rows', coalesce(jsonb_agg(jsonb_build_object(
              'provider_id', z.provider_id, 'name', z.name,
              'adapter', case when z.adapter_state is null then null else jsonb_build_object('state', z.adapter_state, 'fields', to_jsonb(z.admit_fields)) end,
              'qualify', case when not z.qualified then null else jsonb_build_object('passing', to_jsonb(z.passing)) end,
              'onboarding', case when z.ob_id is null then null else jsonb_build_object('id', z.ob_id, 'status', z.ob_status) end) order by z.name, z.provider_id)
              filter (where z.rn <= v_tick_max), '[]'::jsonb))
            from (select f.*, row_number() over (order by f.name, f.provider_id) rn from f) z) end)
          into v_out;
      return v_out;
    end;
  end if;

  create temp table if not exists _l23_inbox on commit drop as select i.kind, i.provider_id from security.layer4_inbox_items_v1() i;
  create temp table if not exists _l23_ob on commit drop as
    select distinct on (o.provider_id) o.id, o.provider_id, o.status, o.stop_reason, o.note, o.result, o.updated_at,
           security.provider_onboarding_stage_v1(o.status, o.stop_reason, o.result) stage
      from pipeline.provider_onboarding o order by o.provider_id, o.created_at desc;

  if p_action = 'operations' then
    with st(key, label, ord, kinds, what) as (values
      ('website', 'Find the website', 1, array['website_needed', 'site_down'], 'The official website is found and checked.'),
      ('pages', 'Find course pages', 2, array['pages_not_found', 'too_few_pages'], 'Each course''s own page is found by its CRICOS code or the university''s listing, and read.'),
      ('adapter', 'Build the adapter', 3, array['nothing_ready', 'onboarding_failed'], 'Sample pages are captured, the AI proposes the adapter, it is applied and qualified.'),
      ('enrich', 'Admit and enrich', 4, array['central_to_approve', 'course_link', 'fee_check', 'not_offered', 'not_on_site', 'counsellor_report'], 'Fields that pass are admitted, central pages fill what pages do not say, courses are enriched.'),
      ('scholarships', 'Scholarships', 5, array['held_scholarship'], 'Scholarship pages are found, read and checked by the AI before they are published.')),
    n as (select
      count(*) filter (where o.status = 'website') website_run, count(*) filter (where o.status = 'queued') website_wait,
      count(*) filter (where o.status in ('course_pages', 'waiting_courses')) pages_run,
      count(*) filter (where o.status in ('capturing', 'proposing', 'applying', 'qualifying')) adapter_run,
      count(*) filter (where o.status = 'scholarships' and o.result->>'phase' = 'enrich') enrich_run, count(*) filter (where o.status = 'waiting_admit') enrich_wait,
      count(*) filter (where o.status = 'scholarships' and coalesce(o.result->>'phase', '') <> 'enrich') sch_run,
      count(*) filter (where o.status = 'done') done, count(*) filter (where o.status = 'stopped') stopped
      from _l23_ob o)
    select jsonb_build_object('as_at', now(), 'can_manage', v_rank >= 6, 'rank', v_rank,
      'done', n.done, 'stopped_onboarding', n.stopped,
      'enrich_review', (select count(*) from pipeline.field_enrich_items f where f.state = 'review'),
      'settings', (select jsonb_build_object('enabled', s.enabled, 'auto_admit', s.auto_admit, 'max_active', s.max_active) from pipeline.provider_onboarding_settings s limit 1),
      'stages', (select jsonb_agg(jsonb_build_object('key', st.key, 'label', st.label, 'order', st.ord, 'what', st.what, 'kinds', to_jsonb(st.kinds),
          'running', case st.key when 'website' then n.website_run when 'pages' then n.pages_run when 'adapter' then n.adapter_run when 'enrich' then n.enrich_run else n.sch_run end,
          'waiting', case st.key when 'website' then n.website_wait
                                 when 'pages' then (select count(*) from pipeline.coverage_provider_discovery d where d.status = 'pending')
                                 when 'adapter' then (select count(*) from pipeline.adapter_builds b where b.wave is not null and coalesce(b.ready, 0) = 0 and b.checked_at is null)
                                 when 'enrich' then n.enrich_wait
                                 else (select count(*) from pipeline.scholarship_ai_reviews r where r.status = 'pending' and coalesce(r.recheck->>'state', 'none') in ('queued', 'leased')) end,
          'stopped', (select count(*) from _l23_inbox i where i.kind = any(st.kinds)),
          'stopped_by_kind', (select coalesce(jsonb_object_agg(k.kind, k.c), '{}'::jsonb) from (select i.kind, count(*) c from _l23_inbox i where i.kind = any(st.kinds) group by 1) k),
          'jobs', (select coalesce(jsonb_agg(a.jobname order by a.sort), '[]'::jsonb) from pipeline.automation_catalogue a where a.layer23_stage = st.key))
        order by st.ord) from st))
      into v_out from n;
    return v_out;
  end if;

  if p_action = 'universities' then
    -- Adapters (Operator and above) as on the old Adapters tab; a Curator sees the universities in onboarding only
    v_list := case when v_rank >= 4 then public.admin_adapters('list', '{}'::jsonb) else jsonb_build_object('can_manage', false, 'can_qualify', false, 'adapters', '[]'::jsonb) end;
    with a as (select x from jsonb_array_elements(coalesce(v_list->'adapters', '[]'::jsonb)) x),
    ids as (select (x->>'provider_id')::uuid provider_id from a),
    extra as (  -- universities in onboarding with no adapter and not in the Firecrawl targets
      select jsonb_build_object('provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2, 'state', s.code,
               'university', true, 'adapter', null, 'target', null, 'qualify', null,
               'pages', (select count(*) from pipeline.coverage_course_pages g where g.provider_id = p.id),
               'pages_read', (select count(*) from pipeline.coverage_course_pages g where g.provider_id = p.id and g.read_status = 'read')) x
        from _l23_ob o join catalogue.providers p on p.id = o.provider_id
        left join ref.countries k on k.id = p.country_id left join ref.subdivisions s on s.id = p.subdivision_id
       where o.provider_id not in (select provider_id from ids)),
    allrows as (select x from a union all select x from extra),
    inbox as (select provider_id, count(*) n, jsonb_object_agg(kind, c) by_kind from (select provider_id, kind, count(*) c from _l23_inbox where provider_id is not null group by 1, 2) z group by 1)
    select jsonb_build_object('as_at', now(), 'can_manage', v_list->'can_manage', 'can_qualify', v_list->'can_qualify', 'can_onboard', v_rank >= 6, 'settings', v_list->'settings',
      'adapters', coalesce(jsonb_agg(r.x || jsonb_build_object(
          'onboarding', case when o.id is null then null else jsonb_build_object('id', o.id, 'status', o.status, 'stage', o.stage, 'phase', o.result->>'phase', 'stop_reason', o.stop_reason, 'note', o.note, 'updated_at', o.updated_at) end,
          'inbox', coalesce(i.n, 0), 'inbox_kinds', coalesce(i.by_kind, '{}'::jsonb))
        order by r.x->>'name'), '[]'::jsonb))
      into v_out
      from allrows r left join _l23_ob o on o.provider_id = (r.x->>'provider_id')::uuid left join inbox i on i.provider_id = (r.x->>'provider_id')::uuid;
    return v_out;
  end if;
  raise exception 'unknown action %', p_action;
end $function$;
