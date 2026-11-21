-- CF-247 s925 (session S1-Fix-IQ00313, P0 IQ-00313, Platform Admin 21 Nov 2026 10:57 AEDT): calendar-v3 never takes a start day from general wording.
--
-- Found live (21 Nov 2026 11:05 AEDT): Edith Cowan University, Bachelor of Science (Occupational Therapy) Honours (CRICOS 086244B, course fbd8ea85), February
-- intake published as 22 February 2027 at 09:26 AEDT (job intake-dates-apply, rule calendar-v3, calendar 2027-Academic-Calendar.pdf). The only course wording
-- behind it is ECU's general sentence "Semester 1 Most courses start in Semester 1 each year, usually in the last week of February": it names Semester 1 for
-- most courses, not for this one, so it does not prove this course's start day. The live audit of every active calendar-v3 day admission (3,548 rows:
-- calendar-v3 1,647, calendar-v3-nearest-start 1,901) found the same wording behind two more ECU February intakes (060895C, 083819C); no other row is
-- backed only by general wording.
--
-- What changes:
--   (s925a) new security.intake_wording_specific_v1(text): the course wording without its general sentences (most / many / some / all / several / a lot of /
--           a number of / the majority of courses, programs, degrees, units or students; usually / generally / typically / normally / in most cases / in general, unless the sentence says
--           "this course", "this program" and the like). Immutable, no setting (a reading rule, not an operational value).
--   (s925b) security.intake_dates_plan_v3 (md5-guarded edit): the study periods are read from the course-specific wording only. When the period or the month is
--           named only in general wording, no route (named period, unique month, Rule B nearest start) takes a start day: the intake takes the year of the
--           calendar's next start in that month within the horizon (year and month, "2027-02"), or stays month only. Live at once (standing mandate,
--           21 Nov 2026 10:07): no switch, no shadow.
--   (s925c) new security.intake_date_day_withdraw_v1(uuid, text, text): the existing withdrawal for the start day only. It reverts the start day the
--           process set (only while the catalogue still holds it), keeps the year, the month, the evidence, the readings, every event, the cohort stages and
--           every lock, appends a withdrawn event whose before_value is the rejected day (so no route admits that day again), places no hold, and refreshes
--           the course's search document.
--   (s925d) this file, once: every active calendar-v3 day admission backed only by general wording (the three ECU intakes, re-found by the same rule when this
--           runs) is taken back to year and month, the stored Website and Zoho items follow in the same transaction (security.intake_projection_reconcile_v1),
--           and the operation is recorded in pipeline.admin_control_events.
-- G1: no new job. G2: no new value. G3 stays 75/48 (no consumer API object changed; data only). Locks: 7,585 before and after (checked below). Spend: none.
-- Parity: head 20261121140000 read live 21 Nov 2026 11:05 AEDT (Pilot #1450 holds 20261121150000); this file is numbered strictly above both.
-- Replaces: nothing (an added check inside security.intake_dates_plan_v3).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the audit reads the stored wording of every active calendar-v3 day admission

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s925_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s925_cron on commit drop as select count(*) n from cron.job where active;

-- (s925a) the course-specific wording
create or replace function security.intake_wording_specific_v1(p_text text) returns text
language sql immutable set search_path to ''
as $f$
  -- IQ-00313 (s925): a sentence about most or many courses, or a hedged one ("usually", "generally") that does not name this course, is general wording
  select coalesce(string_agg(t.x, ' | ' order by t.n), '')
    from regexp_split_to_table(coalesce(p_text, ''), '\s*\|\s*|[.!?;]\s+') with ordinality t(x, n)
   where btrim(t.x) <> ''
     and not (t.x ~* '\m(most|many|some|all|several|a lot of|lots of|a number of|the majority of|majority of)\s+(of\s+)?((our|the|its|these)\s+)?((undergraduate|postgraduate|graduate|international)\s+)?(courses|programs|programmes|degrees|units|students|study options)\M'
              or (t.x ~* '\m(usually|generally|typically|normally|in most cases|in general)\M'
                  and t.x !~* '\mthis\s+(course|program|programme|degree|major|qualification)\M'))
$f$;
comment on function security.intake_wording_specific_v1(text) is
  'CF-247 s925 (IQ-00313): the stored course intake wording without its general sentences ("most courses start in ...", "usually ..."); calendar-v3 reads study periods from this text only.';

-- (s925c) the start-day withdrawal
create or replace function security.intake_date_day_withdraw_v1(p_intake uuid, p_reason text, p_actor text) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare d pipeline.course_intake_dates%rowtype; i catalogue.course_intakes%rowtype; v_adm_before jsonb; v_adm_after jsonb; v_before jsonb; v_after jsonb; v_pub jsonb;
begin
  if coalesce(btrim(p_reason), '') = '' or length(btrim(p_reason)) < 8 then raise exception 'give the reason for the withdrawal' using errcode = '22023'; end if;  -- fixed: a reason of a few words, as the other admin writes
  select * into d from pipeline.course_intake_dates where intake_id = p_intake for update;
  -- the admission from its own record (the latest filled event no later withdrawal undid), as security.intake_date_withdraw_v1
  select e.before_value, e.after_value into v_adm_before, v_adm_after from pipeline.course_intake_date_events e
   where e.intake_id = p_intake and e.outcome = 'filled'
     and not exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = p_intake and w.outcome = 'withdrawn' and w.id > e.id)
   order by e.id desc limit 1;
  if d.intake_id is null or v_adm_after is null then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'no value admitted by the intake-dates process for this intake');
  end if;
  if exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = d.course_id and k.field in ('all', 'intakes', 'intake')) then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'the intakes are locked by hand');
  end if;
  select * into i from catalogue.course_intakes where id = p_intake for update;
  -- only the start day, only when this process set it and the catalogue still holds it
  if not (v_adm_before->>'start_date' is null and v_adm_after->>'start_date' is not null and i.start_date is not distinct from (v_adm_after->>'start_date')::date) then
    return jsonb_build_object('intake_id', p_intake, 'withdrawn', false, 'why', 'the catalogue does not hold a start day this process admitted');
  end if;
  v_before := jsonb_build_object('year', i.intake_year, 'start_date', i.start_date, 'application_deadline', i.application_deadline);
  v_after := jsonb_build_object('year', i.intake_year, 'start_date', null, 'application_deadline', i.application_deadline);
  update catalogue.course_intakes set start_date = null where id = p_intake;
  update pipeline.course_intake_dates set reason = left('start day withdrawn: ' || btrim(p_reason), 500), start_precision = 'year', start_quote = null,
         after_value = v_after, applied_at = now(), publication_state = null, publication_checked_at = null, publication_attempts = 0,
         next_action = security.intake_next_action_v1(d.outcome, 'start day withdrawn', false), next_revisit_at = null
   where intake_id = p_intake;
  insert into pipeline.course_intake_date_events(intake_id, course_id, provider_id, run_at, rule, outcome, reason, next_action, calendar_set, proposal_id, periods, start_precision,
                                                 deadline_kind, before_value, after_value, page_quote, start_quote, deadline_quote, calendar_url, calendar_evidence_id, bounded, related_case)
  values (p_intake, d.course_id, d.provider_id, now(), 'withdrawal', 'withdrawn', left('start day withdrawn: ' || btrim(p_reason) || ' (by ' || coalesce(p_actor, 'unknown') || ')', 500),
          null, d.calendar_set, d.proposal_id, d.periods, 'year', d.deadline_kind, v_before, v_after, d.page_quote, d.start_quote, d.deadline_quote,
          d.calendar_url, d.calendar_evidence_id, false, 'IQ-00313');
  perform search.refresh_course_enrichment_scoped_v1(array[d.course_id], true);
  select jsonb_agg(e) into v_pub from search.course_documents cd, jsonb_array_elements(case when jsonb_typeof(cd.intake_options) = 'array' then cd.intake_options else '[]'::jsonb end) e
   where cd.course_id = d.course_id and e->>'label' = i.intake_label;
  return jsonb_build_object('intake_id', p_intake, 'course_id', d.course_id, 'withdrawn', true, 'held', false, 'before', v_before, 'after', v_after, 'website_source', coalesce(v_pub, '[]'::jsonb),
    'website_verified', not exists (select 1 from jsonb_array_elements(coalesce(v_pub, '[]'::jsonb)) e where e->>'start_date' is not null));
end $f$;
comment on function security.intake_date_day_withdraw_v1(uuid, text, text) is
  'CF-247 s925 (IQ-00313): withdraws only the start day the intake-dates process admitted (year, month, evidence, events and locks kept; no hold placed; a withdrawn event records the rejected day).';
revoke all on function security.intake_date_day_withdraw_v1(uuid, text, text) from public;

-- (s925b) the planner
create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then raise notice '%: already applied', p_sig; return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  raise notice '%: applied', p_sig;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('security.intake_dates_plan_v3(uuid[],integer)', '020a047e45a9c8e82ad45be74a668b2b', 'cf7fff5026511c05be87c5e842a8570d',
  array[$o1$v_raw text; v_pq text; v_named text[];$o1$,
        $o2$     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$' and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
$o2$],
  array[$n1$v_raw text; v_pq text; v_named text[]; v_named_all text[]; v_spec text; v_generic boolean := false;$n1$,
        $n2$     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$' and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    -- P0 IQ-00313 (s925, 21 Nov 2026): a study period or month named only in general wording ("Most courses start in Semester 1 each year, usually in the last
    -- week of February") does not prove this course's start day. The periods are read again from the course-specific wording only (security.intake_wording_specific_v1).
    v_named_all := v_named;
    v_spec := security.intake_wording_specific_v1(v_raw);
    v_pq := security.intake_period_text_canonical_v1(security.intake_period_text_v1(v_spec, v_lists));
    select array_agg(distinct s.period) into v_named
      from jsonb_to_recordset(v_cal) s(period text, kind text)
     where s.kind = 'start' and s.period ~ '^[a-z][a-z _-]*[0-9]+$' and v_pq ~ ('\m' || regexp_replace(s.period, '[ _-]+', '[ _-]*', 'g') || '\M');
    v_generic := coalesce(v_raw, '') <> '' and v_named is null
                 and v_spec !~* ('\m' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m])
                 and (v_named_all is not null or v_raw ~* ('\m' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m]));
    -- P0 IQ-00313 (s925): the intake is named only in general wording. No route (named period, unique month, Rule B nearest start) takes a start day: the
    -- year of the calendar's next start in this month within the horizon is taken (year and month), else the intake stays month only.
    if v_generic then
      select min(s.year) into v_year from jsonb_to_recordset(v_cal) s(kind text, period text, year int, month int, on_date date, year_ok boolean)
       where s.kind = 'start' and s.month = v_m and s.year is not null and s.year_ok
         and (v_named_all is null or s.period = any (v_named_all))
         and (s.on_date >= v_today or (s.on_date is null and make_date(s.year, s.month, 1) >= date_trunc('month', v_today)::date))
         and (r.intake_year is null or s.year = r.intake_year);
      periods := v_named_all; start_precision := 'year'; start_quote := null; deadline_kind := 'not_stated';
      reason := 'the course page names this intake only in general wording (for example "most courses start in ..."): year and month only, no start day';
      if v_year is null or make_date(v_year, v_m, 1) > (date_trunc('month', v_today) + make_interval(months => v_ahead))::date then
        outcome := 'skipped'; start_precision := 'month';
        reason := 'the course page names this intake only in general wording and the calendar has no next start in this month within the horizon (month only)';
      elsif r.intake_year is not null then
        outcome := 'nothing_new';
      elsif exists (select 1 from pipeline.course_intake_date_events w where w.intake_id = r.id and w.outcome = 'withdrawn'
                       and (w.before_value->>'year')::int is not distinct from v_year and w.after_value->>'year' is null) then
        outcome := 'skipped'; start_precision := 'month';
        reason := 'withdrawn: this year was rejected earlier and is not admitted again (a person decides)';
      else
        select min(s.proposal_id::text)::uuid, min(s.url), min(s.evidence_id::text)::uuid into proposal_id, calendar_url, calendar_evidence_id
          from jsonb_to_recordset(v_cal) s(proposal_id uuid, kind text, period text, year int, month int, url text, evidence_id uuid, year_ok boolean)
         where s.kind = 'start' and s.month = v_m and s.year = v_year and s.year_ok and (v_named_all is null or s.period = any (v_named_all));
        outcome := 'filled'; new_year := v_year;
      end if;
      next_action := case when reason like 'withdrawn:%' then 'human_decision_required' else security.intake_next_action_v1(outcome, reason, false) end;
      next_revisit_at := case when reason like 'withdrawn:%' then null else security.intake_revisit_at_v1(next_action) end;
      return next; outcome := null; continue;
    end if;
$n2$]);

-- (s925d) the remediation: every active calendar-v3 day admission backed only by general wording, found by the rule above
do $r$
declare
  v_operation constant text := 'IQ-00313-GENERIC-WORDING-20261121';
  v_reason constant text := 'IQ-00313: the course page names this intake only in general wording ("Most courses start in Semester 1 each year, usually in the last week of February"); the start day is not proved for this course, the year and month are kept';
  v_known constant uuid[] := array['301b33a0-98e0-43f1-8cf2-744507d98413', 'f60ca583-ef95-47d7-9369-989cb368bc8f', '275b1fa8-29a7-481d-b5c9-c7299541923f']::uuid[];  -- 086244B, 060895C, 083819C
  v_ids uuid[]; v_courses uuid[]; v_before jsonb; v_results jsonb := '[]'::jsonb; v_one jsonb; v_recon jsonb; v_n int; r record;
begin
  if exists (select 1 from pipeline.admin_control_events where area = 'intake_dates' and action = 'withdraw_day' and target = v_operation) then
    raise notice '%: already recorded', v_operation; return;
  end if;
  select array_agg(x.intake_id order by x.intake_id), array_agg(distinct x.course_id) into v_ids, v_courses from (
    select d.intake_id, i.course_id, w.raw, security.intake_wording_specific_v1(w.raw) spec, i.intake_label,
           array(select p from unnest(d.periods) p where p ~ '^[a-z][a-z _-]*[0-9]+$') cp
      from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id
      left join pipeline.evidence_artifacts e on e.id = i.evidence_id
      cross join lateral (select security.intake_page_wording_v1(i.course_id, i.evidence_id, e.source_url) raw) w
     where d.outcome in ('filled', 'nothing_new') and d.start_precision = 'day' and d.rule like 'calendar-v3%' and i.status = 'active' and i.start_date is not null) x
   cross join lateral (select security.intake_period_text_canonical_v1(security.intake_period_text_v1(x.raw, true)) pf,
                              security.intake_period_text_canonical_v1(security.intake_period_text_v1(x.spec, true)) ps,
                              '\m' || left(lower(x.intake_label), 3) mon) k
   where coalesce(x.raw, '') <> ''
     and not exists (select 1 from unnest(x.cp) p where k.ps ~ ('\m' || regexp_replace(p, '[ _-]+', '[ _-]*', 'g') || '\M'))
     and x.spec !~* k.mon
     and (exists (select 1 from unnest(x.cp) p where k.pf ~ ('\m' || regexp_replace(p, '[ _-]+', '[ _-]*', 'g') || '\M')) or x.raw ~* k.mon);
  if v_ids is null or not (v_ids @> v_known) then
    raise exception 'guard: the audit did not find the three ECU intakes found live at 11:05 AEDT (found %); nothing changed', v_ids;
  end if;
  if cardinality(v_ids) > 25 then  -- fixed: a set this much larger than the live audit is reviewed by a person first
    raise exception 'guard: % intakes match, the live audit found 3; stop and review', cardinality(v_ids);
  end if;
  perform 1 from catalogue.course_intakes where id = any (v_ids) order by id for update;
  select jsonb_agg(jsonb_build_object('intake', to_jsonb(i), 'events', (select count(*) from pipeline.course_intake_date_events e where e.intake_id = i.id),
                                      'cohort_stages', (select count(*) from pipeline.intake_cohort_stages)) order by i.id) into v_before
    from catalogue.course_intakes i where i.id = any (v_ids);
  for r in select i.id, c.course_code, c.canonical_title from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.id = any (v_ids) order by c.course_code loop
    v_one := security.intake_date_day_withdraw_v1(r.id, v_reason, 'IQ-00313 S1-Fix-IQ00313');
    if not coalesce((v_one->>'withdrawn')::boolean, false) then raise exception 'withdrawal refused for % (%): %', r.course_code, r.id, v_one; end if;
    v_results := v_results || jsonb_build_array(jsonb_build_object('course_code', r.course_code, 'title', r.canonical_title, 'intake_id', r.id, 'before', v_one->'before', 'after', v_one->'after',
                                                                   'website_verified', v_one->'website_verified'));
  end loop;
  v_recon := security.intake_projection_reconcile_v1(v_courses);
  -- the next unattended run looks at these intakes again (their fingerprint is cleared), and the planner as edited above gives no start day for them
  update pipeline.course_intake_dates set inputs_fp = null where intake_id = any (v_ids);
  select count(*) into v_n from security.intake_dates_plan_v3(v_courses, 50) p
   where p.intake_id = any (v_ids) and (p.new_start is not null or p.start_precision = 'day' or p.reason is distinct from
         'the course page names this intake only in general wording (for example "most courses start in ..."): year and month only, no start day');
  if v_n <> 0 then raise exception 'the edited planner still plans a start day, or another reason, for % of these intakes', v_n; end if;
  select count(*) into v_n from security.intake_dates_plan_v3(v_courses, 50) p where p.intake_id = any (v_ids);
  if v_n <> cardinality(v_ids) then raise exception 'the edited planner looked at % of % intakes', v_n, cardinality(v_ids); end if;
  -- in the same transaction: month and year kept, no start day; Website v2 item, stored Website and Zoho items show no start day for these intakes
  select count(*) into v_n from catalogue.course_intakes i where i.id = any (v_ids) and (i.start_date is not null or i.intake_year is null or i.status <> 'active');
  if v_n <> 0 then raise exception '% intakes are not year and month only after the withdrawal', v_n; end if;
  select count(*) into v_n from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id,
         jsonb_array_elements(coalesce(api.website_v2_course_item(i.course_id)->'intakes', '[]'::jsonb)) e
   where i.id = any (v_ids) and e->>'label' = i.intake_label and e->>'start_date' is not null;
  if v_n <> 0 then raise exception 'the Website v2 item still shows a start day for % intakes', v_n; end if;
  select count(*) into v_n from jsonb_array_elements(v_recon) c, jsonb_array_elements(coalesce(c->'website', '[]'::jsonb) || coalesce(c->'zoho', '[]'::jsonb)) w
   where w->>'start_date' is not null and exists (select 1 from catalogue.course_intakes i where i.id = any (v_ids) and i.course_id = (c->>'course_id')::uuid and i.intake_label = w->>'label');
  if v_n <> 0 then raise exception 'a stored Website or Zoho item still shows a start day (% items)', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('intake_dates', 'withdraw_day', v_operation, jsonb_build_object('governance', 'IQ-00313 P0', 'decision', 'Platform Admin 21 Nov 2026 10:57 AEDT (S1-Fix-IQ00313)', 'reason', v_reason,
          'rule', 'calendar-v3', 'migration', '20261121170000', 'spec', 's925', 'fields_changed', jsonb_build_array('start_date'),
          'fields_kept', jsonb_build_array('intake_label', 'intake_year', 'application_deadline', 'source_id', 'evidence_id', 'confidence', 'status', 'readings', 'events', 'cohort_stages', 'locks'),
          'before', v_before, 'results', v_results, 'reconcile', v_recon), null);
  raise notice 'IQ-00313: % intakes taken back to year and month; stored Website and Zoho items reconciled', cardinality(v_ids);
end $r$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s925_locks) then raise exception 'guard: the manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s925_cron) then raise exception 'guard: the active cron jobs changed'; end if;
end $p$;
