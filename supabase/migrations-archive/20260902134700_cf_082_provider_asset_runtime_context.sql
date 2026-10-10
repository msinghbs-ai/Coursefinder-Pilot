begin;
create or replace function public.layer2_runtime_context(p_profile_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','security','pipeline' as $$
declare v pipeline.layer2_source_profiles%rowtype;vv pipeline.layer2_source_profile_versions%rowtype;vr jsonb;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501';end if;
 select * into v from pipeline.layer2_source_profiles where id=p_profile_id;
 if not found or not v.enabled or v.paused or v.domain not in ('course_facts','scholarship','provider_asset') then return null;end if;
 select * into vv from pipeline.layer2_source_profile_versions where id=v.current_version_id;
 if not found or vv.validation_status<>'valid' then return null;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'provider_id',r.acquisition_provider_id,'priority',r.priority,'required_capabilities',r.required_capabilities,'request_overrides',r.request_overrides,'evidence_policy',r.evidence_policy,'fallback_on',r.fallback_on) order by r.priority),'[]'::jsonb)
 into vr from pipeline.layer2_profile_provider_routes r where r.profile_id=v.id and r.enabled;
 return jsonb_build_object('profile_id',v.id,'profile_key',v.profile_key,'domain',v.domain,'source_id',v.source_id,'version_id',vv.id,'version_no',vv.version_no,'configuration',vv.configuration,'routes',vr);
end $$;
revoke all on function public.layer2_runtime_context(uuid) from public,anon,authenticated;
grant execute on function public.layer2_runtime_context(uuid) to service_role;
commit;