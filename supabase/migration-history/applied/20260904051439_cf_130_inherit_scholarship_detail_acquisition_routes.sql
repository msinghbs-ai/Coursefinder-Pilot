with detail_profiles as (
  select dsp.id detail_profile_id,ds.provider_id
  from pipeline.layer2_source_profiles dsp join pipeline.sources ds on ds.id=dsp.source_id
  where dsp.domain='scholarship' and ds.source_type='scholarship_detail' and dsp.enabled and not dsp.paused
), catalogue_profiles as (
  select distinct on (s.provider_id) sp.id catalogue_profile_id,s.provider_id
  from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
  where sp.domain='scholarship' and s.source_type='scholarship_catalogue' and sp.enabled and not sp.paused
  order by s.provider_id,sp.updated_at desc
)
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select d.detail_profile_id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,r.request_overrides,r.evidence_policy,r.fallback_on,'CF-130'
from detail_profiles d join catalogue_profiles c on c.provider_id=d.provider_id join pipeline.layer2_profile_provider_routes r on r.profile_id=c.catalogue_profile_id and r.enabled
on conflict(profile_id,acquisition_provider_id) do nothing;
