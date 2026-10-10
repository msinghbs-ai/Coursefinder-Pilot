-- Package 6 (Supabase security & efficiency): consumer API safety net.
-- Fingerprints the six data functions behind the website, Wix and Zoho APIs with fixed cases.
-- Every Package 6 change runs snapshot -> change -> snapshot -> compare in one transaction and
-- aborts (rolling the change back) if any API output differs. generated_at is ignored.
create table if not exists pipeline.consumer_api_baselines(
  id uuid primary key default extensions.gen_random_uuid(),
  label text not null,
  captured_at timestamptz not null default now(),
  snapshot jsonb not null
);
alter table pipeline.consumer_api_baselines enable row level security;
revoke all on pipeline.consumer_api_baselines from public, anon, authenticated;

create or replace function security.consumer_api_snapshot_v1()
returns jsonb language plpgsql volatile security definer
set search_path to 'pg_catalog','public','api','security'
as $function$
declare res jsonb := '{}'::jsonb; r jsonb; t0 timestamptz; c record;
begin
  for c in select * from (values
    ('search_bachelor_au', $q$select to_jsonb(public.zoho_edge_course_search_v2('bachelor',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,20,0))$q$),
    ('search_master_page2', $q$select to_jsonb(public.zoho_edge_course_search_v2('master',array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,20,20))$q$),
    ('search_has_provider_tuition', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,25,0))$q$),
    ('search_has_scholarship', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,true,null,null,null,null,null,null,null,null,null,null,null,null,null,null,25,0))$q$),
    ('search_tuition_range', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['AU'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,40000,60000,null,null,null,null,25,0))$q$),
    ('search_nz', $q$select to_jsonb(public.zoho_edge_course_search_v2(null,array['NZ'],null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,20,0))$q$),
    ('lookup_080729G', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('080729G'))$q$),
    ('lookup_121174E', $q$select to_jsonb(public.zoho_edge_course_lookup_v1('121174E'))$q$),
    ('providers_university_au', $q$select to_jsonb(public.zoho_edge_provider_search_v1('university','AU',null,20,0))$q$),
    ('filter_country', $q$select to_jsonb(public.zoho_edge_filter_options_v1('country',null,null,50,0))$q$),
    ('filter_subdivision_au', $q$select to_jsonb(public.zoho_edge_filter_options_v1('subdivision','AU',null,50,0))$q$),
    ('reference_bundle', $q$select to_jsonb(public.zoho_edge_reference_bundle_v1())$q$),
    ('website_preview_080729G', $q$select api.website_course_lookup_preview_v1('080729G')$q$)
  ) v(case_name, stmt) loop
    begin
      t0 := clock_timestamp();
      execute c.stmt into r;
      r := r - 'generated_at';
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',true,'md5',md5(r::text),'bytes',length(r::text),'ms',round(extract(epoch from clock_timestamp()-t0)*1000)));
    exception when others then
      res := res || jsonb_build_object(c.case_name, jsonb_build_object('ok',false,'error',sqlerrm));
    end;
  end loop;
  return res;
end $function$;

create or replace function security.consumer_api_compare_v1(p_before jsonb, p_after jsonb)
returns jsonb language sql immutable
as $$
  select coalesce(jsonb_agg(jsonb_build_object('case',k,'before',p_before->k,'after',p_after->k)),'[]'::jsonb)
  from jsonb_object_keys(p_before) k
  where (p_before->k->>'md5') is distinct from (p_after->k->>'md5') or (p_before->k->>'ok') is distinct from (p_after->k->>'ok')
$$;
revoke all on function security.consumer_api_snapshot_v1() from public, anon, authenticated;
revoke all on function security.consumer_api_compare_v1(jsonb,jsonb) from public, anon, authenticated;
