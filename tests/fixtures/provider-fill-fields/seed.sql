-- Guards: Fill fields (Platform Admin 9-10 Nov 2026), database-backed tests: named providers for every Description quality level, then 2,000 more missing ones for volume.
insert into ref.countries(iso_alpha2, name, default_currency_code) values ('AU', 'Australia', 'AUD'), ('NZ', 'New Zealand', 'NZD');
insert into ref.provider_types(code, name) values ('university', 'University'), ('vet', 'Vocational');
insert into ref.subdivisions(code, name, subdivision_type) values ('VIC', 'Victoria', 'state');
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'pdesc.queue_per_run', 'q', 'number', to_jsonb(10), 1, 100, 'providers', 1, 's', 'u'), ('pipeline', 'pdesc.pending_max', 'p', 'number', to_jsonb(40), 1, 100, 'providers', 2, 's', 'u'),
 ('pipeline', 'run_now.pilot_cap', 'c', 'number', to_jsonb(20), 1, 200, 'providers', 3, 's', 'u'), ('pipeline', 'pdesc.queue_cap', 'qc', 'number', to_jsonb(60), 1, 500, 'providers', 4, 's', 'u'),
 ('pipeline', 'pdesc.enabled', 'e', 'number', to_jsonb(1), 0, 1, 'on/off', 5, 's', 'u'), ('pipeline', 'pdesc.reason_min_chars', 'r', 'number', to_jsonb(5), 1, 200, 'chars', 6, 's', 'u'),
 ('pipeline', 'pdesc.ui_preview_minutes', 'm', 'number', to_jsonb(10), 1, 60, 'minutes', 7, 's', 'u'), ('pipeline', 'run_now.jobs', 'j', 'list', '["provider-description-read"]'::jsonb, 0, null, '', 8, 's', 'u'),
 ('pipeline', 'pdesc.countries', 'c', 'list', '["AU","NZ"]'::jsonb, 0, null, '', 9, 's', 'u'), ('pipeline', 'pdesc.provider_types', 'c', 'list', '[]'::jsonb, 0, null, '', 10, 's', 'u'),
 ('pipeline', 'pdesc.acquire_direct', 'c', 'number', to_jsonb(1), 0, 1, '', 11, 's', 'u'), ('pipeline', 'pdesc.ai_usd_max', 'c', 'number', to_jsonb(1), 0, 100, 'USD', 12, 's', 'u'),
 ('pipeline', 'batch.provider_description', 'c', 'number', to_jsonb(3), 1, 100, '', 13, 's', 'u');
insert into pipeline.automation_catalogue(jobname, control_rank) values ('provider-description-read', 6);
insert into cron.job(jobname, active) values ('provider-description-read', true);
insert into pipeline.central_ai_settings values (1, 'fixture/model');

create table public.fx_names (name text primary key, id uuid not null);
create function pg_temp.mk(p_name text, p_desc text default null, p_courses int default 0, p_active_course boolean default true, p_pub text default 'published') returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid(); v_c uuid := (select id from ref.countries where iso_alpha2 = 'AU');
begin
  insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, subdivision_id, provider_type_id, website, description, primary_city, publication_status)
  values (v, 'au-' || p_name, p_name, p_name, v_c, (select id from ref.subdivisions limit 1), (select id from ref.provider_types where code = 'university'), 'https://' || p_name || '.example', p_desc, 'Melbourne', p_pub);
  for i in 1..p_courses loop insert into catalogue.courses(provider_id, lifecycle_status) values (v, case when p_active_course then 'active' else 'inactive' end); end loop;
  insert into public.fx_names values (p_name, v);
  return v;
end $$;

do $$
declare v uuid; r uuid; it uuid;
begin
  -- Missing: no description, no read
  perform pg_temp.mk('missing-one');
  -- Enrichment queued
  v := pg_temp.mk('queued-one'); insert into pipeline.provider_description_reads(provider_id, state) values (v, 'queued');
  -- Enrichment processing
  v := pg_temp.mk('reading-one'); insert into pipeline.provider_description_reads(provider_id, state) values (v, 'reading');
  -- Waiting for human decision: proposed with a pending Layer 4 item
  v := pg_temp.mk('proposed-one'); insert into pipeline.layer4_review_items(status, field_code) values ('pending', 'provider_description') returning id into it;
  insert into pipeline.provider_description_reads(provider_id, state, rule, review_item_id) values (v, 'proposed', 'missing', it);
  -- Held: the reader held its proposal (a retry is due later); and a provider whose machine admission was declined
  v := pg_temp.mk('held-one'); insert into pipeline.provider_description_reads(provider_id, state, rule, reason, read_via, tries, next_try_at) values (v, 'held', 'provider_name_not_proved', 'the page does not name the provider', 'direct', 2, now() + interval '6 hours');
  v := pg_temp.mk('declined-one'); insert into pipeline.provider_description_reads(provider_id, state, rule, reason, read_via) values (v, 'held', 'machine_declined_machine_text_refused_word', 'machine text refused word', 'stored');
  insert into pipeline.provider_description_machine_admissions(provider_id, tier, outcome, reason) values (v, 'stored', 'declined', 'machine text refused word');
  -- Basic registry profile: admitted from register facts
  v := pg_temp.mk('basic-one', 'Basic One is a registered provider in Victoria.', 1); insert into pipeline.layer4_review_items(status, decided_at) values ('approved', now()) returning id into it;
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal, review_item_id) values (v, 'admitted', 'registry_factual', 'registry_factual', jsonb_build_object('description', 'Basic One is a registered provider in Victoria.'), it);
  insert into pipeline.website_sync_items values ('provider', 'au-basic-one', null, jsonb_build_object('description', 'Basic One is a registered provider in Victoria.'));
  -- the same, current: a later admission within the recheck window, which the (stub) selection refuses to read again
  v := pg_temp.mk('basic-current', 'Basic Current is a registered provider.', 0);
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal) values (v, 'admitted', 'registry_factual', 'registry_factual', jsonb_build_object('description', 'Basic Current is a registered provider.'));
  -- Verified published: enriched from a stored page; the Website and Zoho feeds hold the same text
  v := pg_temp.mk('verified-one', 'Verified One teaches at two campuses.', 2);
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal) values (v, 'admitted', 'missing', 'stored', jsonb_build_object('description', 'Verified One teaches at two campuses.'));
  insert into pipeline.website_sync_items values ('provider', 'au-verified-one', null, jsonb_build_object('description', 'Verified One teaches at two campuses.'));
  insert into pipeline.zoho_sync_items values ('provider', 'au-verified-one', null, jsonb_build_object('description', 'Verified One teaches at two campuses.'));
  -- Verified published with Zoho not applicable: the Website feed matches; Zoho does not serve the provider (no active course). Not applicable is not a failure.
  v := pg_temp.mk('webonly-one', 'Webonly One is a small college.', 1, false);
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal) values (v, 'admitted', 'missing', 'direct', jsonb_build_object('description', 'Webonly One is a small college.'));
  insert into pipeline.website_sync_items values ('provider', 'au-webonly-one', null, jsonb_build_object('description', 'Webonly One is a small college.'));
  -- Consumer publication pending: enriched, the Website feed holds older text
  v := pg_temp.mk('pending-one', 'Pending One has a new description.', 1);
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal) values (v, 'admitted', 'missing', 'firecrawl', jsonb_build_object('description', 'Pending One has a new description.'));
  insert into pipeline.website_sync_items values ('provider', 'au-pending-one', null, jsonb_build_object('description', 'Pending One had an old description.'));
  -- Enriched and admitted: no consumer serves it (no courses): both Not applicable
  v := pg_temp.mk('nocourses-one', 'Nocourses One is a provider with no courses.', 0);
  insert into pipeline.provider_description_reads(provider_id, state, rule, read_via, proposal) values (v, 'admitted', 'missing', 'stored', jsonb_build_object('description', 'Nocourses One is a provider with no courses.'));
  -- a description with no admission record
  perform pg_temp.mk('unrecorded-one', 'Unrecorded One was typed in by hand.', 0);
  -- a provider that holds a manual lock (the governed selection refuses it)
  v := pg_temp.mk('locked-one'); insert into pipeline.manual_locks values ('provider', v, 'description');
end $$;
-- volume: 2,000 more providers with no description and no read (the live set is 3,103)
insert into catalogue.providers(stable_key, canonical_name, display_name, country_id, provider_type_id, website, primary_city)
select 'au-bulk-' || g, 'Bulk ' || g, 'Bulk ' || g, (select id from ref.countries where iso_alpha2 = 'AU'), (select id from ref.provider_types where code = 'vet'), case when g % 3 = 0 then null else 'https://b' || g || '.example' end, 'Sydney'
  from generate_series(1, 2000) g;
analyze;
