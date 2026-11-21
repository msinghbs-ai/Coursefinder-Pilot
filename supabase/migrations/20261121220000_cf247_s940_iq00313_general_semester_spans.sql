-- CF-247 s940 (session S1-Fix-IQ00313, P0 IQ-00313, Platform Admin 21 Nov 2026 13:51 AEDT): a general description of the semesters gives month only, never a start day.
--
-- Decision (Platform Admin, 13:51 AEDT): Massey University MY0418 (Master of Veterinary Medicine (Level 9), intake b20bfb7e, July, 12 July 2027 by calendar-v3 on
-- 13 Nov 2026) goes back to July 2027 with no day. General semester descriptions on provider or calendar pages give month only (year and month), never an inferred day.
-- Its only wording is Massey's general description "Semesters One: late February to June Semester Two: July to early November". The stored text is cut into
-- overlapping windows and only the first carries "most courses", so s925 did not catch the second window.
--
-- What changes:
--   (s940a) security.intake_wording_specific_v1 (body md5-guarded, b2a128a1): a sentence that describes a study period as a span of months with a vague bound
--           ("Semester One: late February to June", "Semester Two: July to early November", "Trimester 1: mid-March to the end of June") is also general wording.
--           calendar-v3 (security.intake_dates_plan_v3, unchanged, md5 cf7fff50) reads periods and months from the course-specific wording only, so such an intake
--           takes year and month, or month only. Live at once: no switch, no shadow.
--   (s940b) this file, once: every active calendar-v3 day admission backed only by general wording under the widened rule (Massey MY0418, re-found by the same rule
--           when this runs) goes back to year and month by security.intake_date_day_withdraw_v1 (s925), the stored Website and Zoho items follow in the same
--           transaction, and the operation is recorded in pipeline.admin_control_events.
-- Live audit (21 Nov 2026 13:55 AEDT) of every active calendar-v3 day admission (3,548): the widened rule changes the course-specific wording of one row only, MY0418.
-- G1: no new job. G2: no new value. G3 stays 75/48 (no consumer API object changed; data only). Locks unchanged (checked below). Spend: none.
-- Parity: head 20261121200000 read live 21 Nov 2026 13:55 AEDT; this file is numbered strictly above it.
-- Replaces: the s925 body of security.intake_wording_specific_v1 (same function, one more general-wording pattern).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the audit reads the stored wording of every active calendar-v3 day admission

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5((select prosrc from pg_proc where oid = 'security.intake_wording_specific_v1(text)'::regprocedure)) not in ('b2a128a1eaa26b4ea05fd03a352b9aab', '184872c2b652672715c8b87716361978') then
    raise exception 'guard: security.intake_wording_specific_v1 is not the s925 text this change was written against';
  end if;
  if md5((select prosrc from pg_proc where oid = 'security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) <> 'cf7fff5026511c05be87c5e842a8570d' then
    raise exception 'guard: security.intake_dates_plan_v3 is not the s925 text';
  end if;
end $g$;
create temp table s925_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s925_cron on commit drop as select count(*) n from cron.job where active;

-- (s940a) the course-specific wording
create or replace function security.intake_wording_specific_v1(p_text text) returns text
language sql immutable set search_path to ''
as $f$
  -- IQ-00313 (s925): a sentence about most or many courses, or a hedged one ("usually", "generally") that does not name this course, is general wording
  -- IQ-00313 (s940): so is a sentence that describes a study period as a span of months with a vague bound ("Semester One: late February to June",
  -- "Semester Two: July to early November"): it describes the university's calendar, not this course's start
  select coalesce(string_agg(t.x, ' | ' order by t.n), '')
    from regexp_split_to_table(coalesce(p_text, ''), '\s*\|\s*|[.!?;]\s+') with ordinality t(x, n)
   where btrim(t.x) <> ''
     and not (t.x ~* '\m(most|many|some|all|several|a lot of|lots of|a number of|the majority of|majority of)\s+(of\s+)?((our|the|its|these)\s+)?((undergraduate|postgraduate|graduate|international)\s+)?(courses|programs|programmes|degrees|units|students|study options)\M'
              or (t.x ~* '\m(usually|generally|typically|normally|in most cases|in general)\M'
                  and t.x !~* '\mthis\s+(course|program|programme|degree|major|qualification)\M')
              or t.x ~* '\m(semesters?|trimesters?|terms?|study periods?|teaching periods?)\s*(one|two|three|[1-3])?\s*[:(–-]?\s*((early|mid|late)[ -]|(the )?(start|end|beginning) of )\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(to|–|-|until|through)\s*'
              or t.x ~* '\m(semesters?|trimesters?|terms?|study periods?|teaching periods?)\s*(one|two|three|[1-3])?\s*[:(–-]?\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s*(to|–|-|until|through)\s*((early|mid|late)[ -]|(the )?(start|end|beginning) of )')
$f$;
comment on function security.intake_wording_specific_v1(text) is
  'CF-247 s925, s940 (IQ-00313): the stored course intake wording without its general sentences ("most courses start in ...", "usually ...", "Semester One: late February to June"); calendar-v3 reads study periods from this text only.';
do $m$
begin
  if md5((select prosrc from pg_proc where oid = 'security.intake_wording_specific_v1(text)'::regprocedure)) <> '184872c2b652672715c8b87716361978' then
    raise exception 'guard: security.intake_wording_specific_v1 after this change has body md5 %', md5((select prosrc from pg_proc where oid = 'security.intake_wording_specific_v1(text)'::regprocedure));
  end if;
end $m$;

-- (s940b) the remediation: every active calendar-v3 day admission backed only by general wording, found by the widened rule
do $r$
declare
  v_operation constant text := 'IQ-00313-GENERAL-SEMESTER-SPANS-20261121';
  v_reason constant text := 'IQ-00313: the course page describes the university''s semesters in general ("Semesters One: late February to June Semester Two: July to early November"); the start day is not proved for this course, the year and month are kept';
  v_known constant uuid[] := array['b20bfb7e-44c0-4fe4-bc99-6bacc843f97a']::uuid[];  -- Massey University MY0418, July
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
    raise exception 'guard: the audit did not find Massey MY0418 found live at 13:55 AEDT (found %); nothing changed', v_ids;
  end if;
  if cardinality(v_ids) > 25 then  -- fixed: a set this much larger than the live audit is reviewed by a person first
    raise exception 'guard: % intakes match, the live audit found 1; stop and review', cardinality(v_ids);
  end if;
  perform 1 from catalogue.course_intakes where id = any (v_ids) order by id for update;
  select jsonb_agg(jsonb_build_object('intake', to_jsonb(i), 'events', (select count(*) from pipeline.course_intake_date_events e where e.intake_id = i.id),
                                      'cohort_stages', (select count(*) from pipeline.intake_cohort_stages)) order by i.id) into v_before
    from catalogue.course_intakes i where i.id = any (v_ids);
  for r in select i.id, c.course_code, c.canonical_title from catalogue.course_intakes i join catalogue.courses c on c.id = i.course_id where i.id = any (v_ids) order by c.course_code loop
    v_one := security.intake_date_day_withdraw_v1(r.id, v_reason, 'IQ-00313 S1-Fix-IQ00313 (s940)');
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
  values ('intake_dates', 'withdraw_day', v_operation, jsonb_build_object('governance', 'IQ-00313 P0', 'decision', 'Platform Admin 21 Nov 2026 13:51 AEDT (S1-Fix-IQ00313: Massey MY0418 to month only; general semester descriptions give month only)', 'reason', v_reason,
          'rule', 'calendar-v3', 'migration', '20261121220000', 'spec', 's940', 'fields_changed', jsonb_build_array('start_date'),
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
