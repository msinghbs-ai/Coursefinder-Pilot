-- M2.4.2 A13 — demo-visible Layer 2 provider attempts.
-- Extends the existing rank-4 Layer 2 operations read only; no mutation authority is added.
begin;

do $$
declare v_oid oid; v_def text;
begin
 select p.oid into v_oid
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='security' and p.proname='admin_layer2_ops_read'
   and pg_get_function_identity_arguments(p.oid)='p_operation text, p_args jsonb';
 if v_oid is null then raise exception 'admin_layer2_ops_read not found'; end if;
 select pg_get_functiondef(v_oid) into v_def;

 if position('recent_provider_attempts' in v_def)=0 then
   v_def:=replace(
     v_def,
     '''evidence_summary'',',
     '''recent_provider_attempts'',(select coalesce(jsonb_agg(to_jsonb(x) order by x.completed_at desc nulls last),''[]''::jsonb) from (select a.id,a.job_id,ap.provider_key,ap.display_name provider_name,a.attempt_no,a.status,a.request_url,a.response_http_status,a.response_mime_type,a.raw_evidence_id,a.html_evidence_id,a.screenshot_evidence_id,coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) evidence_id,a.started_at,a.completed_at from pipeline.layer2_provider_attempts a join pipeline.layer2_acquisition_providers ap on ap.id=a.acquisition_provider_id order by a.completed_at desc nulls last,a.created_at desc limit 12)x),''evidence_summary'','
   );
 end if;

 if position('demo_firecrawl_attempt' in v_def)=0 then
   v_def:=replace(
     v_def,
     '''recent_provider_attempts'',',
     '''demo_firecrawl_attempt'',(select to_jsonb(x) from (select a.id,a.job_id,ap.provider_key,ap.display_name provider_name,a.attempt_no,a.status,a.request_url,a.response_http_status,a.response_mime_type,coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) evidence_id,a.started_at,a.completed_at,p.profile_key from pipeline.layer2_provider_attempts a join pipeline.layer2_acquisition_providers ap on ap.id=a.acquisition_provider_id join pipeline.layer2_source_profile_versions pv on pv.id=a.profile_version_id join pipeline.layer2_source_profiles p on p.id=pv.profile_id where ap.provider_key=''firecrawl'' and a.status in (''completed'',''success'',''succeeded'') and p.domain=''course_facts'' and p.enabled and not p.paused and exists(select 1 from pipeline.refresh_policies rp where rp.source_profile_id=p.id and rp.layer=2 and rp.enabled) and coalesce(a.html_evidence_id,a.raw_evidence_id,a.screenshot_evidence_id) is not null order by a.completed_at desc nulls last limit 1)x),''recent_provider_attempts'','
   );
 end if;

 execute v_def;
end $$;

commit;
