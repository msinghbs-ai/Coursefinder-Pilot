-- M2.1 scope correction: Layer 2 acquisition is only for Course and Scholarship enrichment.
-- QILT/PRISMS remain Layer 1 authoritative/context datasets and must not be routed through L2 scraper providers.

update pipeline.layer2_source_profiles
set enabled=false, paused=true, updated_at=now()
where domain='outcomes' or target_entity_type in ('provider_outcome','student_flow');

update pipeline.layer2_profile_provider_routes r
set enabled=false, updated_at=now()
from pipeline.layer2_source_profiles p
where p.id=r.profile_id
  and (p.domain='outcomes' or p.target_entity_type in ('provider_outcome','student_flow'));

create or replace function pipeline.layer2_route_scope_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog,pipeline
as $$
declare v_domain text; v_target text; v_enabled boolean;
begin
  select domain,target_entity_type,enabled into v_domain,v_target,v_enabled
  from pipeline.layer2_source_profiles where id=new.profile_id;
  if v_domain is null then raise exception 'Layer 2 source profile not found' using errcode='23503'; end if;
  if v_domain not in ('course_facts','scholarship') or v_target not in ('course_fact','scholarship') then
    raise exception 'Layer 2 acquisition routes are limited to Course and Scholarship enrichment; QILT/PRISMS remain Layer 1' using errcode='23514';
  end if;
  if not coalesce(v_enabled,false) then
    raise exception 'Layer 2 source profile is not enabled' using errcode='23514';
  end if;
  return new;
end $$;

revoke all on function pipeline.layer2_route_scope_guard() from public,anon,authenticated;

drop trigger if exists trg_layer2_route_scope_guard on pipeline.layer2_profile_provider_routes;
create trigger trg_layer2_route_scope_guard
before insert or update of profile_id,enabled on pipeline.layer2_profile_provider_routes
for each row when (new.enabled is true)
execute function pipeline.layer2_route_scope_guard();

-- Keep historical Source Profile/version rows auditable but hide retired Layer 1 datasets from Layer 2 Admin selectors.
-- The live security.admin_layer2_config_read implementation is also narrowed to enabled Course/Scholarship profiles.
