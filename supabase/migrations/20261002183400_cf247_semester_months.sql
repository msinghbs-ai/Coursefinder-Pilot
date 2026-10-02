-- CF-247 (Decision 228, 2 Oct 2026). Platform Admin, 16:42, by multiple choice: "Semesters to months".
-- About 420 intake reviews wait because the course page names only its study periods ("Semester 1, 2027", "Commencing
-- in Trimester 1", "Term 1 & 3") and the AI check, rightly, would not turn them into months. A university's own
-- calendar says when each period starts.
--  * Each university's start month for each study period comes from its academic calendar, approved by a Platform
--    Admin (Coverage › Attributes › Academic calendars), or set by the Platform Admin by hand from the calendar. Only a
--    period with one start month is used.
--  * A waiting intake review is answered from the calendar only when every period its quotes name has an approved
--    start month, the quotes name no month themselves, the course has no intakes yet and none set by hand, and the quotes
--    do not name a campus outside Australia. The months are written as the course's intakes with the course page as
--    evidence, and the review is closed with both the page's words and the calendar months kept.
--  * The job provider-calendar-intakes answers them every 10 minutes after a calendar is approved or set (an approval
--    request itself writes nothing, so it stays within the time limit of a signed-in request).

-- 1. the approved start month of each study period, per university (latest decision wins; one month only)
create or replace function security.calendar_period_months(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $f$
  select coalesce(jsonb_object_agg(s.period, s.start_month), '{}'::jsonb) from (
    select distinct on (e->>'period') e->>'period' as period, (e->'months'->>0)::int as start_month
      from pipeline.provider_policy_proposals x, jsonb_array_elements(coalesce(x.proposal->'periods', '[]'::jsonb)) e
     where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved'
       and jsonb_typeof(e->'months') = 'array' and jsonb_array_length(e->'months') = 1
     order by e->>'period', x.decided_at desc nulls last) s
$f$;
revoke all on function security.calendar_period_months(uuid) from public, anon, authenticated;

-- 2. the study periods named in a review's quotes ("Semester 1 & 2", "Term 1, 2027", "Trimester one")
create or replace function security.quoted_study_periods(p_quotes text)
returns text[] language sql immutable as $f$
  select coalesce(array_agg(distinct p order by p), '{}') from (
    select regexp_replace(lower(m[1]), '^(study|teaching) period$', '\1_period') || ' ' ||
           case lower(n) when 'one' then '1' when 'two' then '2' when 'three' then '3' when 'four' then '4'
                         when 'i' then '1' when 'ii' then '2' when 'iii' then '3' else n end p
      from regexp_matches(coalesce(p_quotes, ''), '\m(semester|trimester|term|session|study period|teaching period)s?\s+(\d|one|two|three|four|iii|ii|i)\M((?:\s*(?:&|and|,|/)\s*(?:\d)\M)*)', 'gi') m
      cross join lateral unnest(array[m[2]] || coalesce((select array_agg(x[1]) from regexp_matches(coalesce(m[3], ''), '(\d)', 'g') x), '{}')) n) s
$f$;

-- 3. the plan for waiting intake reviews whose quotes name only study periods
create or replace function security.semester_intake_plan_v1(p_provider_id uuid default null)
returns table(review_id uuid, course_id uuid, provider_id uuid, title text, quotes text, periods text[], months int[], outcome text, reason text)
language plpgsql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
begin
  return query
  with r as (
    select l.id, l.entity_id cid, c.provider_id pid, c.canonical_title t,
           (select string_agg(q, ' | ') from jsonb_array_elements_text(coalesce(l.layer3_state->'answer'->'quotes', '[]'::jsonb)) q) qs
      from pipeline.layer4_review_items l join catalogue.courses c on c.id = l.entity_id
     where l.status = 'pending' and l.entity_type = 'course' and l.field_code = 'course_intake' and l.before_value is null and l.evidence_id is not null
       and (p_provider_id is null or c.provider_id = p_provider_id)),
  p as (select r.*, security.quoted_study_periods(r.qs) per, security.calendar_period_months(r.pid) cal from r),
  q as (
    select p.*, (select array_agg(distinct (p.cal->>x)::int order by (p.cal->>x)::int) from unnest(p.per) x where p.cal ? x) mon,
           (select count(*) from unnest(p.per) x where not p.cal ? x) missing
      from p where cardinality(p.per) > 0)
  select q.id, q.cid, q.pid, q.t, q.qs, q.per, q.mon,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'held'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'held'
              when q.cal = '{}'::jsonb then 'no_calendar'
              when q.missing > 0 then 'period_unknown'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'held'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'held'
              else 'answer' end,
         case when q.qs ~* '\m(january|february|march|april|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\M' then 'the quotes also name months'
              when q.qs ~* '\m(hong kong|HK|singapore|malaysia|sarawak|dubai|mauritius|sri lanka|vietnam|china|indonesia|online)\M' then 'the quotes name a campus outside Australia or online study'
              when q.cal = '{}'::jsonb then 'no approved calendar for this university'
              when q.missing > 0 then 'a period has no approved start month'
              when exists (select 1 from catalogue.course_intakes i where i.course_id = q.cid and i.status = 'active') then 'the course already has intakes'
              when exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = q.cid and k.field = 'intakes') then 'intakes set by hand'
              end
    from q;
end $f$;
revoke all on function security.semester_intake_plan_v1(uuid) from public, anon, authenticated;

-- 4. answer the reviews the plan can answer
create or replace function security.semester_intake_apply_v1(p_provider_id uuid default null)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search' as $f$
declare r record; v_ev pipeline.evidence_artifacts%rowtype; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}';
  v_names text[] := array['January','February','March','April','May','June','July','August','September','October','November','December'];
begin
  for r in select * from security.semester_intake_plan_v1(p_provider_id) where outcome = 'answer' loop
    begin
      select * into v_ev from pipeline.evidence_artifacts where id = (select evidence_id from pipeline.layer4_review_items where id = r.review_id);
      perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), v_ev.id, v_ev.source_url, v_ev.content_hash,
        jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', v_names[m], 'source_intake_key', 'calendar:' || r.course_id || ':' || lower(v_names[m])))
                                         from unnest(r.months) m)));
      update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
             escalation_reason = 'Answered from the course page (' || left(r.quotes, 200) || ') and the university''s approved calendar ('
                                 || (select string_agg(initcap(replace(x, '_', ' ')) || ' starts in ' || v_names[(security.calendar_period_months(r.provider_id)->>x)::int], '; ') from unnest(r.periods) x)
                                 || '); Decision 228.'
       where id = r.review_id and status = 'pending';
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select distinct 'courses', 'course_intake', security.coverage_sweep_source(c.provider_id), 'approved', 'CF-CHG-20260915-247; Decision 228 (intakes from the course page and the approved calendar)', now(), now(), now()
      from catalogue.courses c where c.id = any(v_courses)
       and not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_intake' and g.source_id = security.coverage_sweep_source(c.provider_id));
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  return jsonb_build_object('answered', v_ok, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.semester_intake_apply_v1(uuid) from public, anon, authenticated;

-- 5. Platform Admin: set a university's start months by hand (from its calendar); the job answers its waiting reviews
create or replace function public.admin_provider_calendar_set(p_provider_id uuid, p_periods jsonb, p_url text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; v_src uuid; v_clean jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if not exists (select 1 from catalogue.providers where id = p_provider_id) then raise exception 'provider not found'; end if;
  if coalesce(btrim(p_url), '') !~* '^https?://' then raise exception 'the calendar page address is required'; end if;
  select jsonb_agg(jsonb_build_object('period', lower(btrim(e->>'period')), 'months', jsonb_build_array((e->>'month')::int)))
    into v_clean
    from jsonb_array_elements(coalesce(p_periods, '[]'::jsonb)) e
   where lower(btrim(e->>'period')) ~ '^(semester|trimester|term|session|study_period|teaching_period) [1-6]$' and (e->>'month') ~ '^([1-9]|1[0-2])$';
  if v_clean is null then raise exception 'give at least one period (for example semester 1) with a month from 1 to 12'; end if;
  -- the calendar page the months were taken from is kept as a source (and read as evidence by the reader)
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  values (p_provider_id, 'intake_calendar', btrim(p_url), 'Calendar page given by a Platform Admin', 9, 'manual', 'found')
  on conflict on constraint provider_fact_sources_key do nothing;
  select id into v_src from pipeline.provider_fact_sources where provider_id = p_provider_id and kind = 'intake_calendar' and url = btrim(p_url);
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, url, style, proposal, status, decided_by, decided_at, decision_note)
  values (p_provider_id, v_src, 'intake_calendar', 'set by hand', btrim(p_url), 'by_hand', jsonb_build_object('periods', v_clean), 'approved', auth.uid(), now(), left(p_note, 500))
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'calendar_set', btrim(p_url), jsonb_build_object('decision', 'Decision 228', 'proposal_id', v_id, 'provider_id', p_provider_id, 'periods', v_clean), auth.uid());
  return jsonb_build_object('id', v_id, 'to_answer', (select count(*) from security.semester_intake_plan_v1(p_provider_id) r where r.outcome = 'answer'));
end $f$;
revoke all on function public.admin_provider_calendar_set(uuid, jsonb, text, text) from public, anon;
grant execute on function public.admin_provider_calendar_set(uuid, jsonb, text, text) to authenticated;

-- 6. read (Pipeline Operator and above): waiting semester-only intake reviews by university
create or replace function public.admin_semester_intakes_read()
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  return (with pl as materialized (select * from security.semester_intake_plan_v1(null)),
          bo as (select pl.provider_id, jsonb_object_agg(pl.outcome, pl.n) o from (select provider_id, outcome, count(*) n from pl group by 1, 2) pl group by 1),
          pe as (select pl.provider_id, array_agg(distinct x order by x) per from pl, unnest(pl.periods) x group by 1)
    select jsonb_build_object('can_set', security.current_role_rank() >= 6,
      'providers', coalesce(jsonb_agg(x order by (x->>'reviews')::int desc), '[]'::jsonb)) from (
      select jsonb_build_object('provider_id', pl.provider_id, 'provider', coalesce(pv.display_name, pv.canonical_name),
               'reviews', count(*), 'answerable', count(*) filter (where pl.outcome = 'answer'),
               'by_outcome', (select bo.o from bo where bo.provider_id = pl.provider_id),
               'periods', (select pe.per from pe where pe.provider_id = pl.provider_id),
               'months', security.calendar_period_months(pl.provider_id),
               'calendar_url', (select f.url from pipeline.provider_fact_sources f where f.provider_id = pl.provider_id and f.kind = 'intake_calendar' order by f.rank limit 1),
               'sample', min(pl.quotes)) x
        from pl join catalogue.providers pv on pv.id = pl.provider_id
       group by pl.provider_id, pv.display_name, pv.canonical_name) s);
end $f$;
revoke all on function public.admin_semester_intakes_read() from public, anon;
grant execute on function public.admin_semester_intakes_read() to authenticated;

-- 7. approving a parsed calendar reports how many reviews it will answer; the job answers them every 10 minutes
do $p$
declare s text; d text;
  o1 text := $o$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;$o$;
  n1 text := $n$if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;
  if p_action = 'approve' and x.kind = 'intake_calendar' then
    v := jsonb_build_object('to_answer', (select count(*) from security.semester_intake_plan_v1(x.provider_id) r where r.outcome = 'answer'));
  end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from '878f85c1a27d9f5aa16cac9504855a10' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

select cron.schedule('provider-calendar-intakes', '7-59/10 * * * *', $$select security.semester_intake_apply_v1(null)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-calendar-intakes', 'Admission', 63, 'Answer semester-only intakes from calendars',
        'Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Trimester 2") from the university''s approved calendar, where every period named has one start month. The course page stays the evidence; courses with intakes already, or set by hand, are left alone.', 5, false)
on conflict (jobname) do nothing;
