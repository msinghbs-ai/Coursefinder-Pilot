insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select target.id,src.acquisition_provider_id,src.priority,src.enabled,src.required_capabilities,src.request_overrides,src.evidence_policy,src.fallback_on,'CF-CHG-20260904-123'
from pipeline.layer2_source_profiles target
join pipeline.sources ts on ts.id=target.source_id
join lateral (
  select r.* from pipeline.layer2_source_profiles base
  join pipeline.sources bs on bs.id=base.source_id
  join pipeline.layer2_profile_provider_routes r on r.profile_id=base.id
  where bs.provider_id=ts.provider_id and base.domain='scholarship' and base.acquisition_method='scholarship_catalogue'
    and base.id<>target.id and r.enabled
  order by case when base.profile_key like 'au-provider-scholarship-%' then 0 else 1 end,r.priority
) src on true
where target.profile_key like 'au-scholarship-entry-%-cf120'
  and not exists(select 1 from pipeline.layer2_profile_provider_routes x where x.profile_id=target.id and x.acquisition_provider_id=src.acquisition_provider_id)
on conflict do nothing;

-- Providers promoted from a first-party trace may not have an older scholarship profile to clone.
-- In that case attach the standard governed route set from the canonical Federation provider profile as the routing template.
insert into pipeline.layer2_profile_provider_routes(profile_id,acquisition_provider_id,priority,enabled,required_capabilities,request_overrides,evidence_policy,fallback_on,change_control_ref)
select target.id,r.acquisition_provider_id,r.priority,r.enabled,r.required_capabilities,r.request_overrides,r.evidence_policy,r.fallback_on,'CF-CHG-20260904-123'
from pipeline.layer2_source_profiles target
join pipeline.layer2_source_profiles template on template.profile_key='au-provider-scholarship-9cc8ef21-52ec-4c18-849a-598ba1072459'
join pipeline.layer2_profile_provider_routes r on r.profile_id=template.id and r.enabled
where target.profile_key like 'au-scholarship-entry-%-cf120'
  and not exists(select 1 from pipeline.layer2_profile_provider_routes x where x.profile_id=target.id)
on conflict do nothing;
