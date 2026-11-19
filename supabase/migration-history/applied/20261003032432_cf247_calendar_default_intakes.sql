-- CF-247 (3 Oct 2026, 13:30 AEST). Decision 241. Platform Admin, 13:18: a course page bound and read (AAPoly, CRICOS
-- code on the page) names no study period, so the approved calendar had nothing to attach to and the course kept no
-- intake. Multiple choice (13:25): "Yes, but only for VET/TAFE colleges" — an approved calendar's Intake 1 and 2 fill
-- every course of that college whose page names no intake. Universities keep Decision 228's page rule.
-- Rules: Australian providers only, not named University; a course gets the calendar default only when it has an
-- official course page, no intake at all, no intake set or removed by hand, and no waiting intake review with a value;
-- the calendar page is the evidence; the intake keys say calendar_default so the value can be told apart and never
-- overrides a page-stated or hand-set intake later (coverage_apply only adds where there is nothing).
-- Intake 1 = Trimester 1, else Semester 1, else the first period of the calendar; Intake 2 = the second period of the
-- same kind when its month differs (the suggestion the Platform Admin approved on the Academic calendars list).
create or replace function security.calendar_default_months(p_provider_id uuid)
returns int[] language sql stable security definer set search_path to '' as $f$
  -- when the Platform Admin set the months by hand, only those count (a parsed document approved as well adds nothing)
  with m as (
    select coalesce((select jsonb_object_agg(e->>'period', (e->'months'->>0)::int)
                       from (select x.proposal from pipeline.provider_policy_proposals x where x.provider_id = p_provider_id and x.kind = 'intake_calendar' and x.status = 'approved' and x.style = 'by_hand' order by x.decided_at desc nulls last limit 1) h,
                            jsonb_array_elements(coalesce(h.proposal->'periods', '[]'::jsonb)) e
                      where jsonb_typeof(e->'months') = 'array' and jsonb_array_length(e->'months') = 1),
                    security.calendar_period_months(p_provider_id)) cal),
  kinds as (select k.kind, k.ord from (values ('trimester', 1), ('semester', 2), ('term', 3), ('session', 4), ('study_period', 5), ('teaching_period', 6)) k(kind, ord)),
  first_kind as (select k.kind from kinds k, m where (m.cal ? (k.kind || ' 1')) order by k.ord limit 1),
  picked as (
    select (m.cal ->> (f.kind || ' 1'))::int m1, (m.cal ->> (f.kind || ' 2'))::int m2 from m, first_kind f)
  select case when p.m1 is null then '{}'::int[] when p.m2 is null or p.m2 = p.m1 then array[p.m1] else array[p.m1, p.m2] end from picked p
$f$;
revoke all on function security.calendar_default_months(uuid) from public, anon, authenticated;

create or replace function security.calendar_default_intakes_apply_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search' as $f$
declare r record; v_ok int := 0; v_err int := 0; v_last text; v_courses uuid[] := '{}';
  v_names text[] := array['January','February','March','April','May','June','July','August','September','October','November','December'];
begin
  for r in
    with prov as (
      select distinct x.provider_id, security.calendar_default_months(x.provider_id) months
        from pipeline.provider_policy_proposals x join catalogue.providers pv on pv.id = x.provider_id join ref.countries k on k.id = pv.country_id
       where x.kind = 'intake_calendar' and x.status = 'approved' and k.iso_alpha2 = 'AU' and pv.canonical_name !~* '\muniversity\M'),
    cal as (
      select p.provider_id, p.months, s.evidence_id, s.url, s.content_hash
        from prov p join lateral (select f.evidence_id, f.url, f.content_hash from pipeline.provider_fact_sources f
                                   where f.provider_id = p.provider_id and f.kind = 'intake_calendar' and f.evidence_id is not null and f.content_hash is not null
                                   order by (f.found_via = 'manual') desc, f.rank limit 1) s on true
       where cardinality(p.months) > 0)
    select c.id course_id, cal.provider_id, cal.months, cal.evidence_id, cal.url, cal.content_hash
      from cal join catalogue.courses c on c.provider_id = cal.provider_id
     where c.lifecycle_status = 'active'
       and exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
       and not exists (select 1 from catalogue.course_intakes i where i.course_id = c.id)
       and not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = c.id and k.field = 'intakes')
       and not exists (select 1 from pipeline.layer4_review_items l where l.entity_id = c.id and l.field_code = 'course_intake' and l.status = 'pending' and l.proposed_value is not null)
     limit 500
  loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, security.coverage_sweep_source(r.provider_id), r.evidence_id, r.url, r.content_hash,
        jsonb_build_object('intakes', (select jsonb_agg(jsonb_build_object('intake_label', v_names[m], 'source_intake_key', 'calendar_default:' || r.course_id || ':' || lower(v_names[m]))) from unnest(r.months) m)));
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select distinct 'courses', 'course_intake', security.coverage_sweep_source(c.provider_id), 'approved', 'CF-CHG-20260915-247; Decision 241 (college intakes from the approved calendar)', now(), now(), now()
      from catalogue.courses c where c.id = any(v_courses)
       and not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_intake' and g.source_id = security.coverage_sweep_source(c.provider_id));
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('calendar', 'default_intakes', 'Intakes from the approved calendar for college courses whose page names none', jsonb_build_object('courses', v_ok, 'refused', v_err, 'decision', 'Decision 241'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('filled', v_ok, 'refused', v_err, 'last_error', v_last);
end $f$;
revoke all on function security.calendar_default_intakes_apply_v1() from public, anon, authenticated;

select cron.schedule('provider-calendar-defaults', '3-59/10 * * * *', $$select security.calendar_default_intakes_apply_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('provider-calendar-defaults', 'Admission', 64, 'College intakes from the approved calendar',
        'Every 10 minutes: for an Australian college (not a university) with an approved academic calendar, gives Intake 1 and 2 from the calendar to each course that has an official page and no intake at all. Never overrides an intake stated on the page or set by hand; the calendar page is the evidence (Decision 241).', 5, false)
on conflict (jobname) do nothing;
