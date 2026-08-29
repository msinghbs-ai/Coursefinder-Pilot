-- A15: transport-only refresh for Victoria University of Wellington.
-- Canonical catalogue Provider website remains governed separately.
update pipeline.provider_contact_profiles
set base_url='https://www.wgtn.ac.nz',
    domain='wgtn.ac.nz',
    last_error=null,
    updated_at=now()
where provider_id='34616965-b2b7-42a7-8da7-50ffbf120958'::uuid;
