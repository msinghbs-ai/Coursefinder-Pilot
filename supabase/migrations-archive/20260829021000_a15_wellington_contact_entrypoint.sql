-- A15: use the live first-party Wellington International Office page as
-- the contact-discovery entry point because the site root returns HTTP 410 to the worker.
update pipeline.provider_contact_profiles
set base_url='https://www.wgtn.ac.nz/international/contact-us',
    domain='wgtn.ac.nz',
    last_error=null,
    updated_at=now()
where provider_id='34616965-b2b7-42a7-8da7-50ffbf120958'::uuid;
