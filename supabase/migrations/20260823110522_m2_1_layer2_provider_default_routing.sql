insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select p.id,ap.id,10,true,'{}'::jsonb,'{}'::jsonb,
       '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false,"capture_screenshot_on_extraction_failure":false}'::jsonb,
       '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
       'CF-CHG-20260823-029'
from pipeline.layer2_source_profiles p
join pipeline.layer2_acquisition_providers ap on ap.provider_key='direct-http'
on conflict(profile_id,acquisition_provider_id) do nothing;

insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select p.id,ap.id,20,true,'{"javascript":true}'::jsonb,'{}'::jsonb,
       '{"capture_raw":true,"capture_html":true,"capture_screenshot_on_failure":false,"capture_screenshot_on_extraction_failure":true}'::jsonb,
       '["blocked","timeout","403","429","5xx","extraction_failed"]'::jsonb,
       'CF-CHG-20260823-029'
from pipeline.layer2_source_profiles p
join pipeline.layer2_acquisition_providers ap on ap.provider_key='scrape-do'
where p.acquisition_method in ('website','course_catalogue','course_detail','fee_schedule','intake_calendar','english_requirements','scholarship_catalogue','search_endpoint')
on conflict(profile_id,acquisition_provider_id) do nothing;

create or replace function public.layer2_mark_extraction_blocked(p_attempt_id uuid,p_blocker text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','pipeline','public' as $$
declare v_job uuid;begin
 update pipeline.layer2_provider_attempts set status='extraction_failed',extraction_status='blocked',blocker=coalesce(nullif(trim(p_blocker),''),'extraction failed'),completed_at=coalesce(completed_at,now()) where id=p_attempt_id returning job_id into v_job;
 if v_job is null then raise exception 'attempt not found' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'job_id',v_job,'attempt_id',p_attempt_id);
end$$;
revoke all on function public.layer2_mark_extraction_blocked(uuid,text) from public,anon,authenticated;
grant execute on function public.layer2_mark_extraction_blocked(uuid,text) to service_role;
