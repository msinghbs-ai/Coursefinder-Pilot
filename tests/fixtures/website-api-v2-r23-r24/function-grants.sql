-- Function privileges as on live (pg_proc.proacl, read-only, 5 Nov 2026): the api builders run only as their owner; the website wrappers
-- are SECURITY DEFINER and executable by service_role (the edge function's role). "(default)" functions keep PUBLIC execute, as on live.
revoke all on function api.website_v2_provider_campuses(uuid), api.website_v2_scholarship_item(uuid), api.website_text_array(jsonb),
  api.website_v2_provider_logo(uuid), api.website_v2_ranking_summary(uuid), api.website_v2_institution_type(uuid),
  api.website_v2_institution_type_code(uuid), security.ops_remedy_guard_active_v1(), security.website_terms_status_v1(text),
  public.website_v2_providers(jsonb,integer,integer,text), public.website_v2_scholarships(jsonb,integer,integer),
  public.website_v2_scholarship(text) from public;
grant execute on function security.website_terms_status_v1(text), public.website_v2_providers(jsonb,integer,integer,text),
  public.website_v2_scholarships(jsonb,integer,integer), public.website_v2_scholarship(text) to service_role;
