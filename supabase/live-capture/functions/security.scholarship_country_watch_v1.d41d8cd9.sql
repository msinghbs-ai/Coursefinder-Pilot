CREATE OR REPLACE FUNCTION security.scholarship_country_watch_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_raised int := 0; v_resolved int := 0; v_keys text[] := '{}';
begin
  for r in select * from security.scholarship_country_readiness_v1() where active_courses > 0 and (not switched_on or not ready) loop
    v_keys := v_keys || ('scholarship_country:' || r.country_code);
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values ('scholarship_country:' || r.country_code, 'warning', 'scholarships',
            left(case when not r.switched_on then r.country || ' has ' || r.active_courses || ' courses but scholarships are not switched on'
                      else r.country || ': scholarships switched on but not ready' end, 300),
            jsonb_build_object('country', r.country_code, 'active_courses', r.active_courses, 'universities', r.universities,
                               'switched_on', r.switched_on, 'missing', to_jsonb(r.missing), 'registers_planned', r.registers_planned,
                               'next_steps', jsonb_build_array(
                                 'Check the domestic-student wording and government registers in scholarship.country_onboarding',
                                 'Build the planned government registers (Layer 1 record registers) for the country',
                                 'Switch the country on: admin_scholarship_country(code, true, reason) - queues its universities for discovery',
                                 'Check reporting views that list countries (data quality, Zoho reference bundle)')))
    on conflict (check_key) where resolved_at is null do update set title = excluded.title, detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
    v_raised := v_raised + 1;
  end loop;
  update pipeline.platform_issues set resolved_at = now()
   where resolved_at is null and check_key like 'scholarship_country:%' and not (check_key = any(v_keys));
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('raised_or_updated', v_raised, 'resolved', v_resolved, 'at', now());
end $function$
