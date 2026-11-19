grant select on pipeline.layer2_source_profiles to service_role;
grant select on pipeline.layer2_source_profile_versions to service_role;
grant select on pipeline.layer2_profile_provider_routes to service_role;
grant select,update on pipeline.layer2_provider_attempts to service_role;
revoke all on pipeline.layer2_source_profiles,pipeline.layer2_source_profile_versions,pipeline.layer2_profile_provider_routes,pipeline.layer2_provider_attempts from anon,authenticated;
