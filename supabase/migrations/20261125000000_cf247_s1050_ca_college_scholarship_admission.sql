-- CF-247 s1050: Canadian colleges can take the scholarship admission route (S2-Scholarship-Readers, Platform Admin 24 Nov 2026 17:01: recover the Canadian backlog through admission).
-- Measured live: security.scholarship_admission_provider_ok_v1 is false for all ten Canadian colleges with registered hubs (Algonquin, Cambrian, Camosun, Canadore, Conestoga, Durham, George Brown,
-- La Cite, Loyalist, Sheridan) because catalogue.providers.provider_type_id is null for every Canadian provider (the type classifier has rules for AU and NZ only), so 226 scholarship verdicts
-- (George Brown 150, Durham 37, Sheridan 19, Cambrian 8, Camosun 6, Canadore 3, Loyalist 2, Conestoga 1) were refused as "not a university provider in a scholarship country".
-- This change adds one more way to pass: the provider is Canadian, active, has its own non-directory website, and is named in the setting scholarship.ca_college_providers (a list the Platform Admin
-- extends on Settings > Pipeline settings). Universities, Australian and New Zealand providers and every other rule are unchanged.
-- Replaces: security.scholarship_admission_provider_ok_v1(uuid) (same name and argument; md5-guarded edit)
-- Retires: nothing
-- G2: the provider list is a setting. G3: nothing the consumer API reads is touched.

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'scholarship.ca_college_providers', 'Scholarships: Canadian colleges allowed through admission',
        'Canadian providers (colleges and polytechnics without a provider type) that take the scholarship admission route like a university. A provider must also be active, hold its own website and not be a directory site. Add a provider id to include it; remove it to stop.',
        'list', '["7b35d38d-08da-4aec-9110-c60e29dc0b45","c79c40ee-0939-4e2e-b9b3-b4e2d772e667","cc24d184-d9e1-4d8a-b6e5-812b3578d7ac","30f2a374-62e8-4be5-81fd-b94f033ea937","4682bc05-a9de-44bb-ae66-ad02c9717a2d","dc671c35-5660-48ff-bb3b-31be971c0d9f","e924fe06-feb7-472b-9035-4ccebdf9fe67","425b1fad-a4ef-4a21-8590-c7fa9b671107","5675f806-596a-4982-bd4a-f068e013f974","6907453a-faa4-4c60-bc64-e2f2ea476a15"]'::jsonb,
        null, null, 'providers', 1025, 'Scholarships', 'security.scholarship_admission_provider_ok_v1', 'CF-247 s1050: Platform Admin 24 Nov 2026 17:01 (Canadian college scholarship admission recovery)')
on conflict do nothing;

do $e$
declare
  v_def text := pg_get_functiondef('security.scholarship_admission_provider_ok_v1(uuid)'::regprocedure);
  v_old constant text := E'  select security.scholarship_university(p_provider_id)\n      or (security.scholarship_flag_v1(';
  v_new constant text := E'  select security.scholarship_university(p_provider_id)\n      -- s1050 (24 Nov 2026): a listed Canadian college takes the same route (scholarship.ca_college_providers)\n'
    || E'      or (coalesce(security.toolset_setting(''pipeline'', ''scholarship.ca_college_providers''), ''[]''::jsonb) ? p_provider_id::text\n'
    || E'          and exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id\n'
    || E'                       where p.id = p_provider_id and p.lifecycle_status = ''active'' and k.iso_alpha2 = ''CA'' and k.scholarship_ingestion_enabled\n'
    || E'                         and nullif(btrim(coalesce(p.website, '''')), '''') is not null and not security.third_party_host_v1(p.website)))\n'
    || E'      or (security.scholarship_flag_v1(';
begin
  if position('s1050 (24 Nov 2026)' in v_def) > 0 then return; end if;
  if md5(v_def) <> '269f74a985acbc37f1f3b8615efa6254' then raise exception 'guard: security.scholarship_admission_provider_ok_v1 is not the definition this change edits (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the edit anchor must appear exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

do $p$
declare v_bad int; v_ok int;
begin
  select count(*) into v_ok from catalogue.providers p where security.scholarship_admission_provider_ok_v1(p.id) and p.id = any (select (jsonb_array_elements_text(security.toolset_setting('pipeline', 'scholarship.ca_college_providers')))::uuid);
  if v_ok <> 10 then raise exception 'post-check: % of the 10 listed Canadian colleges pass (expected 10)', v_ok; end if;
  raise notice 's1050: % Canadian colleges now pass the scholarship admission provider check', v_ok;
end $p$;
