CREATE OR REPLACE FUNCTION public.admin_reference_sources_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 2 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  update pipeline.important_links l set last_check_http = r.status_code, last_check_at = coalesce(r.created, now()), last_check_request = null,
         last_verified_at = now(), next_verification_at = now() + l.verification_cadence,
         health_status = case when l.retired_at is not null then 'retired' when r.status_code between 200 and 399 then 'healthy' else 'degraded' end
    from net._http_response r where l.last_check_request = r.id;
  return jsonb_build_object(
    'can_edit', v_rank >= 3, 'can_manage', v_rank >= 5,
    'uses', jsonb_build_array(
      jsonb_build_object('key','reference','label','Reference link','help','Shown to staff for looking things up.'),
      jsonb_build_object('key','data_source','label','Data source','help','The platform reads data from it.'),
      jsonb_build_object('key','not_provider_site','label','Never a university website','help','Skipped when finding or checking a university''s own website.'),
      jsonb_build_object('key','not_course_page','label','Never a course page','help','Refused when binding a course page.'),
      jsonb_build_object('key','scholarship_placeholder','label','Scholarship placeholder','help','A scholarship sourced only from here needs a university page before it can be published.'),
      jsonb_build_object('key','logo_directory','label','Logo directory','help','Used only to find university logos.'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher','help','Default source address on Ranking imports.')),
    'categories', jsonb_build_array(
      jsonb_build_object('key','regulatory_authority','label','Regulator or register'),
      jsonb_build_object('key','official_scholarship','label','Official scholarships'),
      jsonb_build_object('key','statistics_data','label','Statistics'),
      jsonb_build_object('key','quality_outcomes','label','Outcomes'),
      jsonb_build_object('key','ranking_publisher','label','Ranking publisher'),
      jsonb_build_object('key','third_party_directory','label','Third-party directory'),
      jsonb_build_object('key','general_web','label','Search, social or listing site'),
      jsonb_build_object('key','international_student_immigration','label','Student visas'),
      jsonb_build_object('key','qualification_framework','label','Qualification framework'),
      jsonb_build_object('key','official_policy_change','label','Policy changes'),
      jsonb_build_object('key','accepted_provider_course_source','label','Accepted course source'),
      jsonb_build_object('key','source_health','label','Source health')),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'country', l.country_code, 'category', l.authority_category,
                 'name', l.authority_name, 'url', l.url, 'domain', l.domain, 'uses', to_jsonb(l.uses), 'enabled', l.enabled,
                 'ref_key', l.ref_key, 'purpose', l.purpose, 'retired', l.retired_at is not null, 'health', l.health_status,
                 'checked_at', coalesce(l.last_check_at, l.last_verified_at), 'http', l.last_check_http, 'checking', l.last_check_request is not null,
                 'scholarships', case when 'scholarship_placeholder' = any(l.uses) then security.reference_placeholder_in_use(l.domain) end,
                 'updated_at', l.updated_at)
               order by l.retired_at is not null, l.authority_category, l.authority_name), '[]'::jsonb) from pipeline.important_links l),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'action', e.action, 'target', e.target, 'detail', e.detail, 'by', u.email) order by e.created_at desc), '[]'::jsonb)
               from (select * from pipeline.admin_control_events where area = 'reference_sources' order by created_at desc limit 20) e left join auth.users u on u.id = e.actor));
end $function$
