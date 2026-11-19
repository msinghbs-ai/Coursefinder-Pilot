CREATE OR REPLACE FUNCTION security.fc_sch_eligible_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- CF-247 scholarship recovery P2 (proposed, off until the Platform Admin switches scholarship.legitimacy_checks_on): evidence-based legitimacy
  -- instead of the course minimum; CF-247 scholarships beyond universities (decision 3 Nov 2026 08:44 §4): the pilot providers only while
  -- scholarship.pilot_only is on
  if security.scholarship_flag_v1('scholarship.legitimacy_checks_on', false) and security.scholarship_pilot_scope_v1(p_provider_id) then
    return security.scholarship_legitimacy_v1(p_provider_id);
  end if;
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  return security.coverage_country(p_provider_id) is distinct from 'AU' or security.fc_courses_v1(p_provider_id) >= security.fc_setting_num_v1('scholarship_min_courses', 30);
end $function$
