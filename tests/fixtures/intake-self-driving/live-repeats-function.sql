-- Guards: F-INT (data population mandate, 9 Nov 2026): security.intake_progress_repeats_v1 exactly as production holds it (md5 4f3d0930df6777edb2a915533e379efb, read 9 Nov 2026 and equal to migration 20261106400000).
create or replace function security.intake_progress_repeats_v1() returns jsonb
language sql stable security definer set search_path to '' as $function$
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
                     p.reader p_reader, p.rule p_rule
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
          when ev.calendar_set is null or ev.page_quote is null or ev.rule is null
               or exists (select 1 from rel where rel.at > ev.p_at and rel.at < ev.run_at and not rel.known) then 'unverified_repeat'
          else 'confirmed' end status from ev)
  select jsonb_build_object(
    'confirmed', (select count(distinct k.intake_id) from k where k.status = 'confirmed'),
    'excluded_source_update', (select count(distinct k.intake_id) from k where k.status = 'excluded_source_update'),
    'excluded_reader_revision', (select count(distinct k.intake_id) from k where k.status = 'excluded_reader_revision'),
    'excluded_setting_change', (select count(distinct k.intake_id) from k where k.status = 'excluded_setting_change'),
    'unverified_repeat', (select count(distinct k.intake_id) from k where k.status = 'unverified_repeat'),
    'examples', (select coalesce(jsonb_agg(jsonb_build_object('status', z.status, 'intake_id', z.intake_id, 'class', z.failure_class, 'decided', z.run_at, 'earlier', z.p_at)), '[]'::jsonb)
                   from (select distinct on (k.status) k.* from k order by k.status, k.run_at desc) z))
$function$;
