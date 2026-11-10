-- CF-247 F-INT Data Delivery (Platform Admin directive 10 Nov 2026 14:02): the EXISTING Data Delivery stream "Intake dates and deadlines" shows the canonical count (1,600 of 31,411 active intakes), the gain over the window, the jobs
-- and the Website match. It did not show the eligible denominator, the new admissions and what is retained, the skipped outcomes apart from the ones that cannot be resolved, the consumer publication status of the decisions, or what blocks the rest.
--   security.data_delivery_intake_v1() (read only, Admin only) NEW: counted live and exactly when the page is read, from the intake tables (no estimate, no forecast, no new table, setting, job or dashboard). It is called by the existing
--   security.data_delivery_v1 for the stream 'int' only, as ONE new key 'intake_delivery' (the response is additive: every existing key is unchanged; the screen treats a missing key as Not measured). Same pattern as 'stages' (cdesc) and 'provider_ai' (pdesc).
--   Denominator: active intakes of active courses; with an exact start date; with a deadline; undated; undated at a provider whose calendar the plan looks at (a decision row exists: ELIGIBLE); undated with no decision row (the provider has no approved
--     calendar, so the plan does not look at them: a source gap, not a failure). Eligible = exact starts + eligible undated.
--   Admissions, in the two windows the stream's gain already uses (data_delivery.net_short_hours and net_long_hours): gross fills (the events the existing gain counts), withdrawn, net, NEW start dates (an intake with no date before), how many of
--     those the catalogue still holds now (RETAINED: the intake's start date is the one the event wrote), and the same for deadlines. By rule (calendar-v3, page-date-v1, ...) for the short window. Last admission and last run time.
--   Skipped outcomes, by cause, kept apart: month_only (the page or calendar prints no day, or no year, for the month: legitimately unresolvable, a day is never invented), page_date_waiting (the stored page prints a full date for the month and the intake
--     has no date yet: the next hourly run checks it, security.intake_page_date_hint_v1; an upper bound, corroboration decides), page_only_unproven (a date no approved calendar start shares and the audience not shown: held for the Platform Admin''s audience rule),
--     identity (E16), no_page_reading, waiting_for_period (next academic year, past), calendar_source, person_decision, other. The latest decision of each intake (now) and the skipped events of the short window, as recorded.
--   Consumer publication: the decisions that hold a date, by publication state, and when it was last checked (the existing check). Blockers: the job switched off, the page route switched off, and the held causes above with their count and kind
--     (technical, decision, source). A figure that cannot be counted returns known false with the error: the rest of Data Delivery is not affected.
--   Cost (live, 10 Nov 2026, EXPLAIN ANALYZE of the same statements, read only): the events, decisions and denominator parts 315 ms, the page-date hint over the 9,262 month-only decisions 630 ms. The statement time-out is 8 s.
-- Definitions (pg_proc.prosrc md5):
--   security.data_delivery_intake_v1() (new) -> ed0361e1ab65cf4525836f4fdd055287
--   security.data_delivery_v1() is edited by several streams, so its edit is ONE ANCHORED LINE applied once to whatever body is live (the pattern of 20261110160000): the 'intake_delivery' line is inserted after the existing 'provider_ai' line,
--   skipped when the body already carries it, and refused (nothing applied) when the anchor is not found exactly once. Read 10 Nov 2026 the live body was 849453412a8b9a448118e7b87362752a; on its own this edit makes 630f8696c18ff05703bb9798ed6fe8fa; on top of the AER edit (04b560cfb6b79758e2b694c96771be33) the result carries both keys.
--   The forward recovery (supabase/held/dd_intake_delivery_forward_recovery.sql) removes only this line, so the keys other streams added stay.
-- Depends on 20261110150000 (the 'provider_ai' key it anchors on) and 20261110170000 (security.intake_page_date_hint_v1). Applying it twice changes nothing.
-- Consumer API (G3): not touched; the Website and Zoho objects, the feed tables and every api.* function are not read or changed. No operational value is written into code (G2): the windows and the switches are read from settings; the only constants are
--   text rules (the cause words) and are marked. No job is added (G1): it runs inside the existing Data Delivery read. No setting, ledger row, read or admission is written; no setting value changes.
-- Replaces: security.data_delivery_v1 is edited in place (one anchored line, one new key 'intake_delivery'); the line is removed by supabase/held/dd_intake_delivery_forward_recovery.sql; otherwise nothing
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration.

do $g$
declare r record;
begin
  for r in select * from (values ('security.data_delivery_v1()'), ('security.pipeline_num_v1(text,numeric)'), ('security.toolset_setting(text,text)'), ('security.intake_page_date_hint_v1(uuid,uuid,text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.course_intake_dates') is null or to_regclass('pipeline.course_intake_date_events') is null or to_regclass('catalogue.course_intakes') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the intake delivery counts (read only; applying again writes the same text)
create or replace function security.data_delivery_intake_v1() returns jsonb
language plpgsql stable security definer set search_path to ''
as $int$
-- data-delivery-intake-v1
declare v_short int := security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int;  -- derived: the existing Data Delivery settings (the same two windows the stream's gain uses)
        v_long int := security.pipeline_num_v1('data_delivery.net_long_hours', 168)::int;
        v_apply boolean := coalesce(security.toolset_setting('pipeline', 'intake_dates.apply_enabled') #>> '{}', 'false') in ('true', '1');   -- fixed: a stored true or 1 is on
        v_page boolean := security.pipeline_num_v1('intake_dates.page_date_admit', 0) >= 1;
        v_out jsonb;
begin
  with act as (select i.id, i.course_id, i.evidence_id, i.intake_label, i.start_date, i.application_deadline
                 from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.status = 'active' and c.lifecycle_status = 'active'),
       dec as (select d.intake_id, d.outcome, d.reason, d.failure_class, d.publication_state, d.publication_checked_at from pipeline.course_intake_dates d),
       den as (select count(*) total, count(*) filter (where a.start_date is not null) exact_start, count(*) filter (where a.application_deadline is not null) with_deadline,
                      count(*) filter (where a.start_date is null) undated,
                      count(*) filter (where a.start_date is null and d.intake_id is not null) undated_eligible,
                      count(*) filter (where a.start_date is null and d.intake_id is null) undated_no_decision
                 from act a left join dec d on d.intake_id = a.id),
       ev as (select e.intake_id, e.rule, e.outcome, e.run_at, e.reason, e.failure_class, (e.after_value->>'start_date')::date sd, (e.after_value->>'application_deadline')::date dl,
                     (e.before_value->>'start_date')::date bsd, (e.before_value->>'application_deadline')::date bdl
                from pipeline.course_intake_date_events e where e.run_at > now() - make_interval(hours => greatest(v_short, v_long)) and e.outcome in ('filled', 'withdrawn', 'skipped')),
       evh as (select e.*, case when e.outcome = 'filled' and e.sd is not null then exists (select 1 from catalogue.course_intakes i where i.id = e.intake_id and i.start_date = e.sd) end held_sd,
                      case when e.outcome = 'filled' and e.dl is not null then exists (select 1 from catalogue.course_intakes i where i.id = e.intake_id and i.application_deadline = e.dl) end held_dl from ev e),
       adm as (select w.h, a.* from (values (v_short), (v_long)) w(h) cross join lateral (
                 select count(*) filter (where e.outcome = 'filled') gross, count(*) filter (where e.outcome = 'withdrawn') withdrawn,
                        count(distinct e.intake_id) filter (where e.outcome = 'filled' and e.sd is not null and e.bsd is null) new_start,
                        count(distinct e.intake_id) filter (where e.outcome = 'filled' and e.sd is not null and e.bsd is null and e.held_sd) retained_start,
                        count(distinct e.intake_id) filter (where e.outcome = 'filled' and e.dl is not null and e.bdl is null) new_deadline,
                        count(distinct e.intake_id) filter (where e.outcome = 'filled' and e.dl is not null and e.bdl is null and e.held_dl) retained_deadline
                   from evh e where e.run_at > now() - make_interval(hours => w.h)) a),
       byrule as (select e.rule, count(*) filter (where e.outcome = 'filled') filled, count(*) filter (where e.outcome = 'withdrawn') withdrawn
                    from ev e where e.run_at > now() - make_interval(hours => v_short) and e.outcome in ('filled', 'withdrawn') group by 1),
       cls as (select 'now'::text scope, d.intake_id, d.reason, d.failure_class, a.course_id, a.evidence_id, a.intake_label, a.start_date from dec d join act a on a.id = d.intake_id where d.outcome = 'skipped'
               union all
               select 'win', e.intake_id, e.reason, e.failure_class, null, null, null, null from ev e where e.outcome = 'skipped' and e.run_at > now() - make_interval(hours => v_short)),
       cl as (select c.scope, c.intake_id, c.course_id, c.evidence_id, c.intake_label, c.start_date,
                     case when c.failure_class = 'course_identity_unresolved' or c.reason like '%(E16%' or c.reason like 'page refused for this course%' then 'identity'
                          when c.reason like 'no stored reading of the page%' then 'no_page_reading'
                          when c.reason like '%(month only)%' then 'month_only'
                          when c.reason like '%page does not show the audience%' or c.reason like '%no approved main calendar start is on that day%' then 'page_only_unproven'
                          when c.failure_class in ('academic_year_unproven', 'stale_calendar_edition', 'waiting_for_next_academic_year') or c.reason like '%which is past%' then 'waiting_for_period'
                          when c.failure_class = 'wrong_institution_or_campus' or c.reason like 'no valid academic calendar%' or c.reason like 'the named period does not start in this month%' then 'calendar_source'
                          when c.failure_class in ('admission_held', 'course_level_exception') then 'person_decision'
                          else 'other' end k from cls c),
       cl2 as (select c.scope, c.intake_id, case when c.scope = 'now' and c.k = 'month_only' and c.start_date is null and security.intake_page_date_hint_v1(c.course_id, c.evidence_id, c.intake_label) then 'page_date_waiting' else c.k end k from cl c),
       sk as (select c.scope, c.k, count(*) n from cl2 c group by 1, 2),
       skw as (select count(*) events, count(distinct c.intake_id) intakes from cl2 c where c.scope = 'win'),
       pub as (select coalesce(d.publication_state, 'not_checked') st, count(*) n from dec d where d.outcome in ('filled', 'nothing_new') group by 1),
       pubm as (select max(d.publication_checked_at) last_checked from dec d),
       last as (select (select max(e.run_at) from pipeline.course_intake_date_events e where e.outcome = 'filled') last_admitted_at, (select max(e.run_at) from pipeline.course_intake_date_events e) last_processed_at),
       bl as (select jsonb_agg(q.b order by (q.b->>'ord')::int) j from (
                select jsonb_build_object('ord', 1, 'code', 'job_off', 'kind', 'technical', 'n', null, 'text', 'The intake job is switched off (intake_dates.apply_enabled), so nothing is admitted until the Platform Admin switches it on.') b where not v_apply
                union all select jsonb_build_object('ord', 2, 'code', 'page_route_off', 'kind', 'technical', 'n', (select n from sk where scope = 'now' and k = 'page_date_waiting'),
                                                   'text', 'The page-date route is off (intake_dates.page_date_admit), so dates the stored pages print are not admitted.') where v_apply and not v_page
                union all select jsonb_build_object('ord', 3, 'code', 'page_only_unproven', 'kind', 'decision', 'n', s.n, 'text', 'The page prints one date that no approved calendar start shares and the audience is not shown. Held for the Platform Admin''s audience rule.') from sk s where s.scope = 'now' and s.k = 'page_only_unproven'
                union all select jsonb_build_object('ord', 4, 'code', 'identity', 'kind', 'source', 'n', s.n, 'text', 'The page is not proved to be the course''s own (E16). Held until the course identity is proved.') from sk s where s.scope = 'now' and s.k = 'identity'
                union all select jsonb_build_object('ord', 5, 'code', 'no_page_reading', 'kind', 'source', 'n', s.n, 'text', 'No stored reading of the course page. The page has to be read before a date can be taken from it.') from sk s where s.scope = 'now' and s.k = 'no_page_reading'
                union all select jsonb_build_object('ord', 6, 'code', 'calendar_source', 'kind', 'source', 'n', s.n, 'text', 'The provider''s calendar is set aside, or does not start the named period in that month. Needs a corrected or approved calendar.') from sk s where s.scope = 'now' and s.k = 'calendar_source'
                union all select jsonb_build_object('ord', 7, 'code', 'no_calendar', 'kind', 'source', 'n', (select undated_no_decision from den), 'text', 'The provider has no approved calendar, so the plan does not look at these intakes yet.') where (select undated_no_decision from den) > 0) q)
  select jsonb_build_object(
    'known', true, 'counted_at', now(), 'unit', 'intakes',
    'denominator', (select jsonb_build_object('active_intakes', total, 'exact_start', exact_start, 'with_deadline', with_deadline, 'undated', undated, 'undated_eligible', undated_eligible, 'undated_no_decision', undated_no_decision,
                                              'eligible', exact_start + undated_eligible) from den),
    'admissions', jsonb_build_object(
      'windows', (select jsonb_agg(jsonb_build_object('hours', a.h, 'gross', a.gross, 'withdrawn', a.withdrawn, 'net', a.gross - a.withdrawn, 'new_start', a.new_start, 'retained_start', a.retained_start,
                                                      'new_deadline', a.new_deadline, 'retained_deadline', a.retained_deadline) order by a.h) from adm a),
      'by_rule', (select coalesce(jsonb_agg(jsonb_build_object('rule', r.rule, 'filled', r.filled, 'withdrawn', r.withdrawn) order by r.filled desc, r.rule), '[]'::jsonb) from byrule r),
      'last_admitted_at', (select last_admitted_at from last), 'last_processed_at', (select last_processed_at from last)),
    'skipped', jsonb_build_object(
      'now', (select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'n', s.n) order by s.n desc, s.k), '[]'::jsonb) from sk s where s.scope = 'now'),
      'window_hours', v_short, 'window_events', (select events from skw), 'window_intakes', (select intakes from skw),
      'window', (select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'n', s.n) order by s.n desc, s.k), '[]'::jsonb) from sk s where s.scope = 'win')),
    'publication', jsonb_build_object('by_state', (select coalesce(jsonb_agg(jsonb_build_object('state', p.st, 'n', p.n) order by p.n desc, p.st), '[]'::jsonb) from pub p), 'last_checked_at', (select last_checked from pubm)),
    'switches', jsonb_build_object('apply_enabled', v_apply, 'page_date_admit', v_page),
    'blockers', coalesce((select j from bl), '[]'::jsonb)) into v_out;
  return v_out;
exception when others then
  return jsonb_build_object('known', false, 'reason', 'the intake delivery counts could not be made: ' || sqlerrm);
end
$int$;
comment on function security.data_delivery_intake_v1() is 'CF-247 F-INT Data Delivery (Platform Admin 10 Nov 2026): the intake stream''s eligible denominator, new and retained admissions in the stream''s two windows, the skipped outcomes by cause (month-only kept apart from the ones a run can still take), the consumer publication state of the decisions and the blockers. Read only, counted live; called by security.data_delivery_v1 for the stream int only, as the key intake_delivery.';
revoke all on function security.data_delivery_intake_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the anchored edit (one line, applied once to whatever body is live)
do $m$
declare v_src text; v_def text; v_c int; v_sig regprocedure := to_regprocedure('security.data_delivery_v1()');
        v_old text := $o$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,$o$;
        v_new text := $n$      'provider_ai', case when s.stream = 'pdesc' then security.data_delivery_pdesc_v1() end,
      'intake_delivery', case when s.stream = 'int' then security.data_delivery_intake_v1() end,$n$;
begin
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  -- Data Delivery is edited by several streams: the edit is one anchored line, applied once to whatever is live
  if position('data_delivery_intake_v1' in v_src) > 0 then raise notice 'security.data_delivery_v1(): already carries the intake key'; return; end if;
  v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'security.data_delivery_v1(): the anchor line (the provider_ai key) must be found exactly once (found %): nothing applied', v_c; end if;
  execute replace(v_def, v_old, v_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
  if position('data_delivery_intake_v1' in v_src) = 0 then raise exception 'security.data_delivery_v1(): the intake key was not added'; end if;
  raise notice 'security.data_delivery_v1(): applied';
end $m$;

-- ----------------------------------------------------------------------------------------------------------------------------------------- register, post-check
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.data_delivery_intake_v1', 'Platform', 'F-INT: the intake stream''s eligible denominator, new and retained admissions, skipped causes (month-only apart), consumer publication state and blockers for Data Delivery (read only, live)', 'active', '{}', '20261110171000')
on conflict do nothing;

do $post$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_intake_v1()'::regprocedure)) <> 'ed0361e1ab65cf4525836f4fdd055287' then raise exception 'post-check: security.data_delivery_intake_v1 does not have the recorded body md5'; end if;
  if position('data_delivery_intake_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: Data Delivery does not call the intake delivery counts'; end if;
  if position('data_delivery_pdesc_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 or position('data_delivery_cdesc_stages_v1' in (select p.prosrc from pg_proc p where p.oid = 'security.data_delivery_v1()'::regprocedure)) = 0 then raise exception 'post-check: an existing Data Delivery call was lost'; end if;
end $post$;
