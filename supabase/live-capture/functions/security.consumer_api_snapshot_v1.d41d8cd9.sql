CREATE OR REPLACE FUNCTION security.consumer_api_snapshot_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'api', 'security'
AS $function$
-- 20261119104500 (s720): the before/after evidence of an admission batch (pipeline.consumer_api_baselines, Decision 163): the same frozen reads,
-- admit.consumer_snapshot_page_size rows each, cheap reads first and the two free-text searches (about 7 s each) last, stopping at
-- admit.consumer_snapshot_budget_ms (the reads it skips are marked). A statement-timeout cancel cannot be caught, so the budget is checked
-- before each read.
declare res jsonb := '{}'::jsonb; r jsonb; t0 timestamptz; c record; v_start timestamptz := clock_timestamp();
        v_page int := greatest(1, security.pipeline_num_v1('admit.consumer_snapshot_page_size', 5)::int);
        v_budget int := greatest(1000, security.pipeline_num_v1('admit.consumer_snapshot_budget_ms', 6000)::int);
begin
  for c in select * from (values
    ('search_has_provider_tuition', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_has_scholarship', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_tuition_range', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,40000,60000,null,null,null,null,%1$s,0))$q$),
    ('search_nz', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['NZ'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('lookup_080729G', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('080729G'))$q$),
    ('lookup_121174E', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('121174E'))$q$),
    ('providers_university_au', $q$select to_jsonb(public.zoho_edge_provider_search_v1('university','AU',null,%1$s,0))$q$),
    ('filter_country', $q$select to_jsonb(public.zoho_edge_filter_options_v1('country',null,null,50,0))$q$),
    ('filter_subdivision_au', $q$select to_jsonb(public.zoho_edge_filter_options_v1('subdivision','AU',null,50,0))$q$),
    ('reference_bundle', $q$select to_jsonb(public.zoho_edge_reference_bundle_v1())$q$),
    ('website_preview_080729G', $q$select api.website_course_lookup_preview_v1('080729G')$q$),
    ('search_bachelor_au', $q$select to_jsonb(public.zoho_edge_course_search_v2('bachelor',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,0))$q$),
    ('search_master_page2', $q$select to_jsonb(public.zoho_edge_course_search_v2('master',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,%1$s,%1$s))$q$)
  ) v(case_name, stmt) loop
    if extract(epoch from clock_timestamp() - v_start) * 1000 > v_budget then
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok', null, 'skipped', 'time budget', 'budget_ms', v_budget));
      continue;
    end if;
    begin
      t0 := clock_timestamp();
      execute format(c.stmt, v_page) into r;
      r := r - 'generated_at';
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',true,'md5',md5(r::text),'bytes',length(r::text),'ms',round(extract(epoch from clock_timestamp()-t0)*1000),'rows_asked',v_page));
    exception when others then
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',false,'error',sqlerrm));
    end;
  end loop;
  return res;
end $function$
