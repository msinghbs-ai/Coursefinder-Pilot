-- CF-247 (Decision 228 switched on, 3 Oct 2026 02:53 AEST). Platform Admin, in chat: "yes calendars".
-- Parts 2 and 3 of Decision 228, prepared on 2 Oct as migrations 20261002183410 and 20261002183420 and never applied
-- (their database approval prompts were cancelled). They are applied here unchanged except for the md5 guard on
-- public.admin_provider_policy_decide, which changed at 20261003000300 (one approved document per university); those two
-- files are removed from the repository so that it matches the live database.
-- What this does: a waiting intake review whose course page names only study periods ("Semester 1", "Trimester 2") is
-- answered from the university's approved calendar when every period named has one start month; the months are written
-- as the course's intakes with the course page as evidence (job provider-calendar-intakes, every 10 minutes). A calendar
-- never adds a start to a course whose page names none; courses with intakes already, or set by hand, are left alone.
-- No calendar is approved here: at 02:55 none is approved, so the first run answers nothing until a Platform Admin
-- approves a calendar (Layer 4 Review › Attributes › Academic calendars) or sets start months by hand.

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
  if md5(s) is distinct from 'ed78f0a0bd0534430e194c543846edc5' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

select cron.schedule('provider-calendar-intakes', '7-59/10 * * * *', $$select security.semester_intake_apply_v1(null)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-calendar-intakes', 'Admission', 63, 'Answer semester-only intakes from calendars',
        'Every 10 minutes: answers a waiting intake review whose course page names only its study periods ("Semester 1", "Trimester 2") from the university''s approved calendar, where every period named has one start month. The course page stays the evidence; courses with intakes already, or set by hand, are left alone.', 5, false)
on conflict (jobname) do nothing;
