-- CF-247 (Decision 228, 2 Oct 2026), part 2 of 3: answering semester-only intake reviews from approved calendars.

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
