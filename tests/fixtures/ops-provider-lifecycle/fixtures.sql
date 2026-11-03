-- Ops workstream G fixtures: every case of the provider identity check, investigations, lifecycle events and the onboarding hold, on the migrated
-- fixture database. Each block raises on a wrong answer and prints one NOTICE line when it passes. Fixture data only.
create or replace function fx.ok(p_cond boolean, p_what text) returns void language plpgsql as $$
begin if not coalesce(p_cond, false) then raise exception 'FAILED: %', p_what; end if; end $$;
create or replace function fx.set(p_key text, p_value jsonb) returns void language sql as $$
  update pipeline.platform_toolset_settings set value = p_value where toolset_key = 'pipeline' and key = p_key $$;
create or replace function fx.as_user(p_rank int) returns void language sql as $$ update fx.caller set uid = '00000000-0000-0000-0000-0000000000a1', rank = p_rank where id = 1 $$;
create or replace function fx.prov(p_name text, p_site text, p_email text default null, p_key text default null) returns uuid language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into catalogue.providers(id, canonical_name, display_name, website, email, stable_key, country_id)
  values (v, p_name, p_name, p_site, p_email, p_key, (select id from ref.countries where iso_alpha2 = 'AU'));
  insert into catalogue.courses(provider_id) values (v), (v);
  return v;
end $$;
create or replace function fx.finding(p uuid, p_code text) returns text language sql stable as $$
  select state from pipeline.provider_identity_findings where provider_id = p and check_code = p_code $$;

-- the catalogue as the cases need it ---------------------------------------------------------------------------------------------------------
insert into ref.countries(iso_alpha2, name) values ('AU', 'Australia'), ('ZZ', 'Retiring land');
insert into pipeline.sources(id, label, url, last_success_at) values ('b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'CRICOS Providers, Courses and Locations', 'https://data.gov.au/data/dataset/cricos', now());
insert into pipeline.important_links values ('coursefinder-directory.com', true, null, '{not_provider_site}', 'third_party_directory');
create table fx.p (k text primary key, id uuid);
insert into fx.p values
 ('newgen', fx.prov('NEWGEN EDUCATION', 'https://info@newgen.edu.au', 'admissions@newgen.edu.au', 'provider:cricos:03871f')),
 ('fits', fx.prov('Example College of Design', 'https://www.exampledesign.edu.au', 'info@exampledesign.edu.au')),
 ('scotch', fx.prov('Scotch College', 'https://www.scotch.vic.edu.au')),
 ('toorak', fx.prov('Toorak College', 'https://www.toorak.vic.edu.au')),
 ('cegep', fx.prov('Cégep de Matane', 'https://www.cegep-matane.qc.ca')),
 ('cegep2', fx.prov('Cégep de Sherbrooke', 'https://www.cegepsherbrooke.qc.ca')),
 ('alpha', fx.prov('Alpha Health Institute', 'https://www.sharedhost.com.au')),
 ('beta', fx.prov('Beta Aviation Academy', 'https://sharedhost.com.au/beta')),
 ('hays1', fx.prov('Hays International College', 'https://www.hays.edu.au')),
 ('hays2', fx.prov('Hays International College Pty Ltd', 'https://hays.edu.au/brisbane')),
 ('zeta', fx.prov('Zeta Training Services', 'https://www.randomsite.com.au', 'info@zetaskills.edu.au')),
 ('zeta_mail', fx.prov('Omega Learning Hub', 'https://www.ohub-site.com.au', 'enrol@ohub-site.com.au')),
 ('acts', fx.prov('Abacus Counselling, Training and Supervision Limited', 'https://www.acts.co.nz')),
 ('rgs', fx.prov('Rockhampton Grammar School; The Rockhampton English Language Academy', 'https://www.rgs.qld.edu.au')),
 ('cfnt', fx.prov('Centre de formation des Nouvelles-Technologies', 'https://www.cfnt.qc.ca')),
 ('mercy', fx.prov('Mercy College', 'https://mercy.catholic.edu.au')),
 ('tenison', fx.prov('Tenison Woods College', 'https://tenison.catholic.edu.au')),
 ('redirect', fx.prov('Hilton Academy', 'https://www.hilton.edu.au')),
 ('parked', fx.prov('Parkview Institute', 'https://www.parkview.edu.au')),
 ('directory', fx.prov('Delta Institute', 'https://www.coursefinder-directory.com/delta')),
 ('ended', fx.prov('Ended Registration College', 'https://www.endedcollege.edu.au')),
 ('departed', fx.prov('Departed College', 'https://www.departedcollege.edu.au')),
 ('successor', fx.prov('Successor College', 'https://www.successorcollege.edu.au')),
 ('merged', fx.prov('Merged College', 'https://www.mergedcollege.edu.au')),
 ('outage', fx.prov('Outage Institute', 'https://www.outageinstitute.edu.au')),
 ('archived_by_register', fx.prov('Gone College', 'https://www.gonecollege.edu.au')),
 ('zz1', fx.prov('Northland Polytechnic', 'https://www.northlandpoly.zz')),
 ('zz2', fx.prov('Southland Polytechnic', 'https://www.southlandpoly.zz'));
update catalogue.providers set country_id = (select id from ref.countries where iso_alpha2 = 'ZZ') where id in (select id from fx.p where k in ('zz1', 'zz2'));
update catalogue.providers set canonical_source_id = 'b5680d74-49c5-49a5-b198-a625f3e3fdcf' where id = (select id from fx.p where k = 'newgen');
insert into catalogue.provider_registrations(provider_id, source_id, registration_scheme, registration_code, status, checked_at)
select id, 'b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'cricos', '03871F', 'active', now() - interval '38 days' from fx.p where k = 'newgen';
insert into catalogue.provider_registrations(provider_id, registration_scheme, registration_code, status, valid_to, checked_at)
select id, 'cricos', '09999Z', 'ended', current_date - 20, now() - interval '20 days' from fx.p where k = 'ended';
insert into pipeline.evidence_artifacts(source_url, evidence_type, storage_path, review_state, metadata)
select 'https://info@newgen.edu.au', 'layer2_html_snapshot', 'layer2/v2/qualification/x/' || id || '/homepage.html', 'unreviewed', jsonb_build_object('provider_id', id) from fx.p where k = 'newgen';
insert into pipeline.provider_onboarding(provider_id, status, stop_reason) select id, 'stopped', 'needs_source_discovery' from fx.p where k = 'newgen';
insert into pipeline.scholarship_discovery_providers(provider_id, website, site_origin) select id, 'https://www.hilton.edu.au', 'https://lesuisse.edu.au' from fx.p where k = 'redirect';
insert into pipeline.provider_website_checks(provider_id, url, action, state, verdict, result, checked_at)
select id, 'https://www.parkview.edu.au', 'check', 'done', 'failed', '{"answers": true, "title": "parkview.edu.au - Buy this domain", "redirected": false}', now() from fx.p where k = 'parked';
insert into pipeline.layer1_provider_departures(provider_id, run_id, courses_retired, status) select id, gen_random_uuid(), 2, 'needs_review' from fx.p where k = 'departed';
insert into pipeline.layer1_provider_departures(provider_id, run_id, courses_retired, status, successor_provider_id)
select (select id from fx.p where k = 'merged'), gen_random_uuid(), 2, 'needs_review', (select id from fx.p where k = 'successor');
select security.provider_archive_apply_v1((select id from fx.p where k = 'archived_by_register'), 'layer1_departure', 'All its registered courses left the register', null, false);

-- 1 the check: each finding where it belongs, nowhere else ---------------------------------------------------------------------------------------
do $$
declare r jsonb := security.provider_identity_check_v1();
begin
  perform fx.ok(fx.finding((select id from fx.p where k = 'newgen'), 'website_malformed') = 'open', 'NEWGEN website malformed');
  perform fx.ok((select count(*) from pipeline.provider_identity_findings where check_code = 'website_malformed') = 1, 'only NEWGEN is malformed');
  perform fx.ok(fx.finding((select id from fx.p where k = 'newgen'), 'domain_shared') is null and fx.finding((select id from fx.p where k = 'newgen'), 'identity_unconfirmed') is null,
                'a malformed website is not also tested as a domain (no domain is derived from it)');
  perform fx.ok(fx.finding((select id from fx.p where k = 'alpha'), 'domain_shared') = 'open' and fx.finding((select id from fx.p where k = 'beta'), 'domain_shared') = 'open', 'unrelated providers sharing a domain');
  perform fx.ok(fx.finding((select id from fx.p where k = 'hays1'), 'domain_shared') is null, 'two records of one provider are related, not shared');
  perform fx.ok(not exists (select 1 from pipeline.provider_identity_findings where check_code = 'domain_shared' and provider_id in (select id from fx.p where k in ('scotch', 'toorak', 'cegep', 'cegep2'))),
                'state school and provincial zones are not one shared domain');
  perform fx.ok(security.provider_identity_domain_v1('https://www.scotch.vic.edu.au/x') = 'scotch.vic.edu.au' and security.provider_identity_domain_v1('https://www.cegep-matane.qc.ca') = 'cegep-matane.qc.ca'
                and security.provider_identity_domain_v1('https://a.b.example.com') = 'example.com' and security.provider_identity_domain_v1('https://foo.ac.nz') = 'foo.ac.nz', 'registrable domains');
  perform fx.ok(fx.finding((select id from fx.p where k = 'zeta'), 'identity_unconfirmed') = 'open', 'a domain fitting neither name nor email');
  perform fx.ok(fx.finding((select id from fx.p where k = 'zeta_mail'), 'identity_unconfirmed') is null, 'a domain matching the contact email domain is not flagged');
  perform fx.ok(fx.finding((select id from fx.p where k = 'acts'), 'identity_unconfirmed') is null, 'initials (acts) fit the name');
  perform fx.ok(fx.finding((select id from fx.p where k = 'fits'), 'identity_unconfirmed') is null, 'a domain holding a name word fits');
  perform fx.ok(fx.finding((select id from fx.p where k = 'rgs'), 'identity_unconfirmed') is null, 'initials of one of several listed names fit');
  perform fx.ok(fx.finding((select id from fx.p where k = 'cfnt'), 'identity_unconfirmed') is null, 'French articles are left out of initials');
  perform fx.ok(fx.finding((select id from fx.p where k = 'mercy'), 'identity_unconfirmed') is null, 'a provider''s own subdomain fits its name');
  perform fx.ok(fx.finding((select id from fx.p where k = 'mercy'), 'domain_shared') is null and fx.finding((select id from fx.p where k = 'tenison'), 'domain_shared') is null,
                'subdomains of one organisation are not a shared site');
  perform fx.ok(fx.finding((select id from fx.p where k = 'directory'), 'identity_unconfirmed') is null, 'a third-party directory is left to its own refusal');
  perform fx.ok(fx.finding((select id from fx.p where k = 'redirect'), 'redirected_or_parked') = 'open', 'a stored site mapping ended on another domain');
  perform fx.ok(fx.finding((select id from fx.p where k = 'parked'), 'redirected_or_parked') = 'open', 'a parked home page title');
  perform fx.ok(fx.finding((select id from fx.p where k = 'ended'), 'register_changed') = 'open' and fx.finding((select id from fx.p where k = 'departed'), 'register_changed') = 'open', 'register changes');
  perform fx.ok((select count(*) from pipeline.integration_issues where fingerprint like 'provider_identity:%') = 5, 'one integration issue per finding kind');
  perform fx.ok((select severity from pipeline.integration_issues where fingerprint = 'provider_identity:website_malformed') = 'P1', 'malformed is P1');
  perform fx.ok((select (select id from fx.p where k = 'newgen') = any (provider_ids) from pipeline.integration_issues where fingerprint = 'provider_identity:website_malformed'), 'issue names the provider');
  raise notice 'pass 1: the check finds each kind where it belongs (%)', r->'by_check';
end $$;

-- 2 a second run: seen again, nothing duplicated; a corrected website clears its finding and corrects its investigation ----------------------
do $$
declare v_n int := (select count(*) from pipeline.provider_identity_findings); v_i int := (select count(*) from pipeline.provider_identity_investigations);
begin
  perform security.provider_identity_check_v1();
  perform fx.ok((select count(*) from pipeline.provider_identity_findings) = v_n and (select count(*) from pipeline.provider_identity_investigations) = v_i, 'nothing duplicated');
  perform fx.ok((select observations from pipeline.provider_identity_findings where provider_id = (select id from fx.p where k = 'zeta') and check_code = 'identity_unconfirmed') = 2, 'seen again');
  perform fx.ok((select observed from pipeline.integration_issues where fingerprint = 'provider_identity:website_malformed') = 2, 'issue observed, not re-created');
  update catalogue.providers set website = 'https://www.zetaskills.edu.au' where id = (select id from fx.p where k = 'zeta');
  perform security.provider_identity_check_v1();
  perform fx.ok(fx.finding((select id from fx.p where k = 'zeta'), 'identity_unconfirmed') = 'cleared', 'corrected website clears');
  perform fx.ok((select state from pipeline.provider_identity_investigations where provider_id = (select id from fx.p where k = 'zeta') order by id desc limit 1) = 'corrected', 'investigation corrected');
  raise notice 'pass 2: second run idempotent; a correction clears the finding and the investigation';
end $$;

-- 3 NEWGEN: blocked by evidence, no candidate from the email; a person's candidate is checked, never saved; only a verified check proposes ------
do $$
declare v uuid := (select id from fx.p where k = 'newgen'); i pipeline.provider_identity_investigations; v_chk uuid;
begin
  select * into i from pipeline.provider_identity_investigations where provider_id = v and state in ('open', 'blocked_evidence', 'proposed');
  perform fx.ok(i.state = 'blocked_evidence', 'NEWGEN blocked_evidence by name');
  perform fx.ok(jsonb_array_length(i.candidates) = 0, 'no candidate derived from the email address');
  perform fx.ok(i.evidence @> '[{"kind": "register", "code": "03871F"}]' and i.evidence @> '[{"kind": "contact_email", "domain": "newgen.edu.au"}]'
                and i.evidence @> '[{"kind": "stored_snapshot"}]' and i.evidence @> '[{"kind": "register_source"}]', 'the platform''s evidence recorded');
  perform fx.ok((select note from jsonb_array_elements(i.evidence) e, lateral (select e->>'note' note) z where e->>'kind' = 'contact_email') like '%not evidence of a website%', 'email marked not evidence');
  -- a person adds a candidate with its source; the existing check is queued (it never saves a website)
  perform fx.as_user(3);
  begin perform public.admin_provider_identity('candidate', jsonb_build_object('provider_id', v, 'url', 'https://newgen.edu.au/', 'source', 'Study Australia provider page, CRICOS 03871F'));
        raise exception 'a Curator added a candidate'; exception when sqlstate '42501' then null; end;
  perform fx.as_user(5);
  begin perform public.admin_provider_identity('candidate', jsonb_build_object('provider_id', v, 'url', 'https://newgen.edu.au/', 'source', 'email'));
        raise exception 'a candidate without provenance'; exception when others then perform fx.ok(sqlerrm like 'say where the candidate comes from%', 'provenance required: ' || sqlerrm); end;
  perform public.admin_provider_identity('candidate', jsonb_build_object('provider_id', v, 'url', 'https://newgen.edu.au/', 'source', 'Study Australia provider page, CRICOS 03871F'));
  select id into v_chk from pipeline.provider_website_checks where provider_id = v and action = 'check';
  perform fx.ok(v_chk is not null and not exists (select 1 from pipeline.provider_website_checks where provider_id = v and action = 'change'), 'a check, never a change');
  -- the check answers "likely" (name only): still blocked
  update pipeline.provider_website_checks set state = 'done', verdict = 'likely', checked_at = now(), result = '{"answers": true, "name_basis": "name_in_page", "final_url": "https://newgen.edu.au/"}' where id = v_chk;
  perform security.provider_identity_check_v1();
  perform fx.ok((select state from pipeline.provider_identity_investigations where provider_id = v and closed_at is null) = 'blocked_evidence', 'likely is not verified');
  -- verified (CRICOS code on the home page): proposed; the website is not changed
  update pipeline.provider_website_checks set verdict = 'verified', why = 'the provider''s CRICOS code 03871F is on the home page',
         result = '{"answers": true, "cricos_on_site": true, "cricos_code": "03871F", "final_url": "https://newgen.edu.au/"}' where id = v_chk;
  perform security.provider_identity_check_v1();
  select * into i from pipeline.provider_identity_investigations where provider_id = v and closed_at is null;
  perform fx.ok(i.state = 'proposed' and i.verification->>'check_id' = v_chk::text, 'verified check proposes');
  perform fx.ok((select website from catalogue.providers where id = v) = 'https://info@newgen.edu.au', 'never applied by the platform');
  raise notice 'pass 3: NEWGEN blocked_evidence; candidate needs provenance; likely stays blocked; verified proposes; website untouched';
end $$;

-- 4 stored candidates are checked only with identity.candidate_check_on ---------------------------------------------------------------------
do $$
declare v uuid := (select id from fx.p where k = 'alpha');
begin
  insert into pipeline.provider_website_checks(provider_id, url, action, state, verdict, result, checked_at)
  values (v, 'https://www.sharedhost.com.au', 'check', 'done', 'failed', '{"answers": true, "register_site": "https://www.alphahealth.edu.au"}', now());
  perform security.provider_identity_check_v1();
  perform fx.ok(fx.finding(v, 'identity_unconfirmed') = 'open', 'the register lists another site');
  perform fx.ok((select candidates @> '[{"provenance": "register", "url": "https://www.alphahealth.edu.au"}]' from pipeline.provider_identity_investigations where provider_id = v and closed_at is null), 'register candidate recorded');
  perform fx.ok(not exists (select 1 from pipeline.provider_website_checks where provider_id = v and url = 'https://www.alphahealth.edu.au'), 'no check while candidate_check_on is 0');
  perform fx.set('identity.candidate_check_on', '1');
  perform security.provider_identity_check_v1();
  perform fx.ok((select count(*) from pipeline.provider_website_checks where provider_id = v and url = 'https://www.alphahealth.edu.au' and action = 'check') = 1, 'one check queued');
  perform security.provider_identity_check_v1();
  perform fx.ok((select count(*) from pipeline.provider_website_checks where provider_id = v and url = 'https://www.alphahealth.edu.au') = 1, 'not queued twice');
  perform fx.set('identity.candidate_check_on', '0');
  raise notice 'pass 4: stored candidates checked only when switched on, once, never a change';
end $$;

-- 5 auto remedies: investigate, stop an onboarding loop, plan lifecycle; registered with the right authority ------------------------------------
do $$
declare v uuid := (select id from fx.p where k = 'newgen'); v_issue bigint := (select id from pipeline.integration_issues where fingerprint = 'provider_identity:website_malformed'); r jsonb;
begin
  update pipeline.provider_onboarding set status = 'website', stop_reason = null where provider_id = v;
  perform fx.ok(not (security.provider_onboarding_remedy_stop_verify_v1(v_issue)->>'passed')::boolean, 'loop detected before the remedy');
  r := security.provider_onboarding_remedy_stop_v1(v_issue);
  perform fx.ok((r->>'changed')::boolean and (select status || '/' || stop_reason from pipeline.provider_onboarding where provider_id = v) = 'stopped/needs_source_discovery', 'remedy stops the loop');
  perform fx.ok((security.provider_onboarding_remedy_stop_verify_v1(v_issue)->>'passed')::boolean, 'verify passes');
  perform fx.ok(not (security.provider_onboarding_remedy_stop_v1(v_issue)->>'changed')::boolean, 'remedy is idempotent');
  perform fx.ok((security.provider_identity_remedy_investigate_verify_v1(v_issue)->>'passed')::boolean, 'investigation verify passes');
  perform fx.ok((select count(*) from pipeline.ops_root_causes where code like 'provider_%') = 6, 'six root causes');
  perform fx.ok((select array_agg(code order by code) from pipeline.ops_remedies where authority = 'auto') = array['provider_identity_investigate', 'provider_lifecycle_plan', 'provider_onboarding_stop_invalid_website'], 'auto remedies are the three non-destructive ones');
  perform fx.ok((select array_agg(code order by code) from pipeline.ops_remedies where authority = 'admin') = array['provider_lifecycle_cascade', 'provider_website_correction'], 'correction and cascade are admin');
  perform fx.ok((select action_fn is null from pipeline.ops_remedies where code = 'provider_website_correction'), 'no automatic correction function');
  raise notice 'pass 5: auto remedies stop waste and record; correction and cascade stay with the Platform Admin';
end $$;

-- 6 lifecycle proposals from register evidence; the register archive recorded as executed; reviewed plans --------------------------------------
do $$
declare e pipeline.provider_lifecycle_events;
begin
  select * into e from pipeline.provider_lifecycle_events where provider_id = (select id from fx.p where k = 'departed');
  perform fx.ok(e.state = 'planned' and e.transition = 'deregistered' and e.source = 'layer1_departure' and security.provider_lifecycle_evidence_ok_v1(e.evidence), 'departure proposed and planned');
  perform fx.ok((select array_agg(x->>'key' order by x->>'key') from jsonb_array_elements(e.plan->'items') x) @> array['aer_records', 'campuses', 'consumer_projection', 'courses', 'enrichment_plans',
                'entry_requirements', 'layer1_references', 'layer23_work', 'layer4_items', 'onboarding', 'provider_contacts', 'providers', 'scholarships', 'search_projection', 'source_mappings', 'tasks'], 'plan covers every relationship');
  perform fx.ok((select transition || '/' || successor_provider_id::text from pipeline.provider_lifecycle_events where provider_id = (select id from fx.p where k = 'merged')) = 'merged/' || (select id from fx.p where k = 'successor'), 'successor makes it merged');
  perform fx.ok((select state from pipeline.provider_lifecycle_events where provider_id = (select id from fx.p where k = 'ended')) = 'planned', 'ended registration proposed');
  perform fx.ok((select state || '/' || source from pipeline.provider_lifecycle_events where provider_id = (select id from fx.p where k = 'archived_by_register')) = 'executed/layer1_departure', 'register archive recorded as executed');
  perform fx.ok((select lifecycle_status from catalogue.providers where id = (select id from fx.p where k = 'departed')) = 'active', 'a proposal changes nothing');
  perform security.provider_identity_check_v1();
  perform fx.ok((select count(*) from pipeline.provider_lifecycle_events) = 4, 'proposals are not duplicated');
  raise notice 'pass 6: register evidence proposes and plans; existing archives recorded; nothing changed';
end $$;

-- 7 decisions: authority, the cascade switch, AI-only evidence refused ----------------------------------------------------------------------
do $$
declare v_e bigint := (select id from pipeline.provider_lifecycle_events where provider_id = (select id from fx.p where k = 'departed'));
begin
  perform fx.as_user(5);
  begin perform public.admin_provider_lifecycle('approve', jsonb_build_object('event', v_e, 'note', 'register says gone')); raise exception 'a PIM Operator approved'; exception when sqlstate '42501' then null; end;
  begin perform public.admin_provider_lifecycle('propose', jsonb_build_object('provider_id', (select id from fx.p where k = 'fits'), 'transition', 'closed', 'effective_date', current_date,
          'evidence', '[{"kind": "ai", "ref": "model said the site looks closed"}]')); raise exception 'AI-only evidence accepted';
  exception when others then perform fx.ok(sqlerrm like 'authoritative evidence is required%', 'AI-only evidence refused: ' || sqlerrm); end;
  perform fx.as_user(6);
  perform public.admin_provider_lifecycle('approve', jsonb_build_object('event', v_e, 'note', 'Register departure confirmed'));
  begin perform public.admin_provider_lifecycle('execute', jsonb_build_object('event', v_e)); raise exception 'executed with cascade off';
  exception when others then perform fx.ok(sqlerrm like 'lifecycle transitions are switched off%', 'cascade_on 0 holds: ' || sqlerrm); end;
  perform fx.ok((select lifecycle_status from catalogue.providers where id = (select id from fx.p where k = 'departed')) = 'active', 'nothing executed');
  raise notice 'pass 7: approve needs the Platform Admin; AI-only evidence refused; execution held while lifecycle.cascade_on is 0';
end $$;

-- 8 execution and reversal of a retirement -------------------------------------------------------------------------------------------------
do $$
declare v uuid := (select id from fx.p where k = 'departed'); v_e bigint := (select id from pipeline.provider_lifecycle_events where provider_id = v); v_course uuid; v_sch uuid; r jsonb;
        v_job uuid; v_job_other uuid; v_l4c uuid; v_l4s uuid; v_cp uuid; v_onb uuid; v_plan uuid;
begin
  select id into v_course from catalogue.courses where provider_id = v limit 1;
  insert into scholarship.scholarships(provider_id) values (v) returning id into v_sch;
  insert into search.course_documents select id, provider_id from catalogue.courses where provider_id = v;
  insert into pipeline.admin_jobs(scope, state) values (v::text, 'queued') returning id into v_job;
  insert into pipeline.admin_jobs(args, state) values (jsonb_build_object('providers', jsonb_build_array((select id from fx.p where k = 'fits'))), 'queued') returning id into v_job_other;
  insert into pipeline.layer4_review_items(entity_type, entity_id, status) values ('course', v_course, 'pending') returning id into v_l4c;
  insert into pipeline.layer4_review_items(entity_type, entity_id, status) values ('scholarship', v_sch, 'pending') returning id into v_l4s;
  insert into pipeline.provider_contact_profiles(provider_id) values (v) returning id into v_cp;
  insert into pipeline.provider_onboarding(provider_id, status) values (v, 'course_pages') returning id into v_onb;
  insert into pipeline.enrich_plan_runs(provider_id, state) values (v, 'queued') returning id into v_plan;
  insert into pipeline.uni_adapters values (v, true, true, now());
  perform fx.set('lifecycle.cascade_on', '1');
  -- a plan older than lifecycle.plan_max_age_hours is built again first
  update pipeline.provider_lifecycle_events set planned_at = now() - interval '2 days' where id = v_e;
  begin perform public.admin_provider_lifecycle('execute', jsonb_build_object('event', v_e)); raise exception 'stale plan executed';
  exception when others then perform fx.ok(sqlerrm like '%older than lifecycle.plan_max_age_hours%', 'stale plan refused'); end;
  perform public.admin_provider_lifecycle('replan', jsonb_build_object('event', v_e));
  r := public.admin_provider_lifecycle('execute', jsonb_build_object('event', v_e));
  perform fx.ok(r->>'state' = 'executed', 'executed');
  perform fx.ok(exists (select 1 from security.provider_hidden_v1 where provider_id = v), 'hidden through the existing hide');
  perform fx.ok((select cancel_requested from pipeline.admin_jobs where id = v_job) and not (select cancel_requested from pipeline.admin_jobs where id = v_job_other), 'its task cancelled by request, others untouched');
  perform fx.ok((select status from pipeline.layer4_review_items where id = v_l4c) = 'superseded' and (select status from pipeline.layer4_review_items where id = v_l4s) = 'superseded', 'course and scholarship reviews superseded');
  perform fx.ok((select paused from pipeline.provider_contact_profiles where id = v_cp), 'contact discovery paused');
  perform fx.ok((select status || '/' || stop_reason from pipeline.provider_onboarding where id = v_onb) = 'stopped/retired', 'onboarding stopped');
  perform fx.ok((select state from pipeline.enrich_plan_runs where id = v_plan) = 'cancelled', 'queued plan cancelled');
  perform fx.ok(not (select enabled from pipeline.uni_adapters where provider_id = v), 'adapter off (existing archive)');
  perform fx.ok((select count(*) from catalogue.courses where provider_id = v) = 2 and (select count(*) from scholarship.scholarships where provider_id = v) = 1, 'nothing deleted');
  -- downstream verification waits for the search refresh, then passes
  perform fx.ok(not (security.provider_lifecycle_verify_v1(v_e)->>'passed')::boolean, 'not verified while the projection still lists it');
  delete from search.course_documents where provider_id = v;  -- the fixture plays the search refresh the archive requested
  perform security.provider_identity_check_v1();
  perform fx.ok((select (execution->'verification'->>'passed')::boolean from pipeline.provider_lifecycle_events where id = v_e), 'verified and recorded by the job');
  -- reversal
  begin perform public.admin_provider_lifecycle('reverse', jsonb_build_object('event', v_e)); raise exception 'reversed without a reason'; exception when others then perform fx.ok(sqlerrm = 'a reason is required', 'reason required'); end;
  r := public.admin_provider_lifecycle('reverse', jsonb_build_object('event', v_e, 'note', 'Register lists it again'));
  perform fx.ok((select lifecycle_status || '/' || publication_status from catalogue.providers where id = v) = 'active/published', 'restored as it was');
  perform fx.ok((select status from pipeline.layer4_review_items where id = v_l4c) = 'pending' and (select status from pipeline.layer4_review_items where id = v_l4s) = 'pending', 'reviews reopened');
  perform fx.ok(not (select paused from pipeline.provider_contact_profiles where id = v_cp) and (select status from pipeline.provider_onboarding where id = v_onb) = 'course_pages', 'contacts and onboarding put back');
  perform fx.ok((select enabled from pipeline.uni_adapters where provider_id = v), 'adapter back on (existing restore)');
  perform security.provider_identity_check_v1();
  perform fx.ok((select count(*) from pipeline.provider_lifecycle_events where provider_id = v) = 1, 'a reversed decision is not proposed again from the same evidence');
  raise notice 'pass 8: execution archives through the existing path, stops its work, verifies downstream; reversal puts everything back';
end $$;

-- 9 temporarily unavailable is not retirement: held, not hidden; the onboarding tick waits and resumes --------------------------------------
do $$
declare v uuid := (select id from fx.p where k = 'outage'); v_e bigint; v_onb uuid;
begin
  insert into pipeline.provider_onboarding(provider_id, status, updated_at) values (v, 'course_pages', now() - interval '1 hour') returning id into v_onb;
  v_e := (public.admin_provider_lifecycle('propose', jsonb_build_object('provider_id', v, 'transition', 'temporarily_unavailable', 'effective_date', current_date,
          'evidence', '[{"kind": "first_party", "ref": "https://www.outageinstitute.edu.au notice: closed for maintenance until 1 Dec"}]'::jsonb, 'note', 'Site down for maintenance'))->>'event')::bigint;
  perform fx.ok((select plan->'items' @> '[{"key": "consumer_projection", "effect": "No change"}]' from pipeline.provider_lifecycle_events where id = v_e), 'plan: no consumer change');
  perform public.admin_provider_lifecycle('approve', jsonb_build_object('event', v_e, 'note', 'Hold while down'));
  perform public.admin_provider_lifecycle('execute', jsonb_build_object('event', v_e));
  perform fx.ok((select lifecycle_status || '/' || publication_status from catalogue.providers where id = v) = 'active/published', 'not retired, still published');
  perform fx.ok(security.provider_lifecycle_held_v1(v), 'held');
  truncate fx.stepped; perform security.provider_onboarding_tick_v1();
  perform fx.ok(not exists (select 1 from fx.stepped where onboarding_id = v_onb), 'the tick does not step a held provider');
  perform fx.ok((select status from pipeline.provider_onboarding where id = v_onb) = 'course_pages', 'its onboarding row is kept, not stopped');
  perform public.admin_provider_lifecycle('reverse', jsonb_build_object('event', v_e, 'note', 'Site back up'));
  truncate fx.stepped; perform security.provider_onboarding_tick_v1();
  perform fx.ok(exists (select 1 from fx.stepped where onboarding_id = v_onb), 'stepped again after reversal');
  raise notice 'pass 9: temporary unavailability holds work without retiring or hiding; reversal resumes it';
end $$;

-- 10 country retirement: every provider through the same path, ingestion off, all reversible -----------------------------------------------
do $$
declare v_c uuid := (select id from ref.countries where iso_alpha2 = 'ZZ'); v_e bigint;
begin
  v_e := (public.admin_provider_lifecycle('propose', jsonb_build_object('scope', 'country', 'country_id', v_c, 'transition', 'retired', 'effective_date', current_date,
          'evidence', '[{"kind": "admin_record", "ref": "Platform Admin decision: country ZZ leaves the catalogue"}]'::jsonb, 'note', 'Country leaves'))->>'event')::bigint;
  perform fx.ok((select (plan->>'providers_total')::int from pipeline.provider_lifecycle_events where id = v_e) = 2, 'plan names both providers');
  perform public.admin_provider_lifecycle('approve', jsonb_build_object('event', v_e, 'note', 'Retire ZZ'));
  perform public.admin_provider_lifecycle('execute', jsonb_build_object('event', v_e));
  perform fx.ok((select count(*) from catalogue.providers where country_id = v_c and lifecycle_status = 'archived') = 2, 'both archived');
  perform fx.ok((select not provider_ingestion_enabled and not course_ingestion_enabled and not scholarship_ingestion_enabled and student_search_enabled from ref.countries where id = v_c),
                'ingestion off; student search left to the Platform Admin');
  perform public.admin_provider_lifecycle('reverse', jsonb_build_object('event', v_e, 'note', 'Country stays'));
  perform fx.ok((select count(*) from catalogue.providers where country_id = v_c and lifecycle_status = 'active') = 2, 'both restored');
  perform fx.ok((select provider_ingestion_enabled and course_ingestion_enabled and scholarship_ingestion_enabled from ref.countries where id = v_c), 'flags put back');
  raise notice 'pass 10: country retirement cascades per provider and reverses';
end $$;

-- 11 switches off: no check, no investigation, no proposal -----------------------------------------------------------------------------------
do $$
declare v_f int := (select count(*) from pipeline.provider_identity_findings);
begin
  perform fx.set('identity.check_on', '0');
  perform fx.ok(security.provider_identity_check_v1()->>'skipped' is not null, 'check off');
  perform fx.set('identity.check_on', '1'); perform fx.set('identity.investigate_on', '0'); perform fx.set('lifecycle.propose_on', '0'); perform fx.set('identity.issue_on', '0');
  perform fx.ok((security.provider_identity_check_v1()->'investigations'->>'skipped') is not null, 'investigations off');
  perform fx.ok((security.provider_identity_check_v1()->'lifecycle'->>'skipped') is not null, 'proposals off');
  perform fx.set('identity.investigate_on', '1'); perform fx.set('lifecycle.propose_on', '1'); perform fx.set('identity.issue_on', '1');
  raise notice 'pass 11: each switch stops its part';
end $$;
