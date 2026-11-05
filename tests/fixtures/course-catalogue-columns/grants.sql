-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: the production grants of every live function the fixture loads
-- (read read-only from fxcwkweaxjtknorudmwp, 5 Nov 2026 20:50 AEDT). No blanket grant: run.sh compares each ACL with production.
\set ON_ERROR_STOP on
do $$ declare f text; begin
  -- {postgres, authenticated, service_role}
  foreach f in array array['public.admin_read(text,jsonb)', 'security.admin_course_page_fast(jsonb)', 'security.admin_course_page_unfiltered_fast(jsonb)',
    'security.admin_course_page_search_state(jsonb)', 'security.current_role_rank()'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f); execute format('grant execute on function %s to authenticated', f); execute format('grant execute on function %s to service_role', f);
  end loop;
  -- {postgres, service_role}
  foreach f in array array['security.admin_course_page_fast_base(jsonb)', 'security.university_group_provider_ids(text)',
    'public.ui_courses_decision_page(integer,integer,text,text,text,uuid,text,text,text,text,text,boolean,boolean,boolean,boolean,numeric,text,text,text,boolean,boolean,text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f); execute format('grant execute on function %s to service_role', f);
  end loop;
  -- {postgres} only
  execute 'revoke all on function api.website_v2_label_month(text) from public, anon, authenticated, service_role';
  -- security.pipeline_num_v1 and security.provider_university_groups keep the default (PUBLIC), as in production
end $$;
