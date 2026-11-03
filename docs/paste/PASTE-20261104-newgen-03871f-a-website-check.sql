-- CF-247 ops workstream G, NEWGEN EDUCATION (CRICOS 03871F), step A of 2 (Platform Admin decision, mandate 3 Nov 2026 15:52: "authorise an
-- evidence-backed correction only"). PASTE FILE. Not applied by any migration. Run by the Integration Controller through governance.
-- What it does: asks the platform's own website check (pipeline.provider_website_checks, action 'check', the coverage-sweep site_check worker,
--   the same check the Adapter builder runs) to read https://newgen.edu.au/ for provider 2db6cb5e. A check NEVER saves a website. It records the
--   page fetch: whether the home page answers, the final address after redirects, the title, and whether CRICOS code 03871F is on the page
--   (verdict 'verified' only then, or when it is the site the register lists). Step B corrects the website only on that verified result.
-- Why the candidate is https://newgen.edu.au/ (not derived from the email address admissions@newgen.edu.au):
--   * Study Australia (Australian Government), provider page "PHOENIX COLLEGE OF AUSTRALIA PTY LTD", CRICOS provider code 03871F, provider type
--     RTO, "Visit website" href https://newgen.edu.au/, the description names Newgen Education; addresses Unit 2, 11 Cordelia St, South
--     Brisbane QLD 4101 and Unit 1 108 Johnston St, Collingwood VIC 3066.
--     https://search.studyaustralia.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178 (read 3 Nov 2026 15:58 AEDT)
--   * Study Melbourne (State Government of Victoria), the same provider record: CRICOS 03871F, href https://newgen.edu.au/, the same two addresses.
--     https://coursesearch.studymelbourne.vic.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178 (read 16:00 AEDT)
--   * The platform's register record: catalogue.provider_registrations d8e28854 (cricos 03871F, active, checked 26 Sep 2026, evidence 8cbc0745,
--     CRICOS Courses.csv), source b5680d74 "CRICOS Providers, Courses and Locations" (data.gov.au). The malformed value "https://info@newgen.edu.au"
--     came with the register record (provider created 11 Aug 2026 from that source); a third-party mirror of the register (oneuedu.com) shows the
--     same malformed link, so the register's own website field is the defect.
--   * Not used as evidence: the email domain; nexgen.edu.au (another provider: Nexgen Institute of Australia, CRICOS 04151H, per Study Australia).
-- Not yet held (why this is step A): the primary CRICOS register page (cricos.education.gov.au) and training.gov.au (RTO 45633, per a third-party
--   mirror; legal name PHOENIX COLLEGE OF AUSTRALIA PTY LTD, ABN 75 638 913 550) could not be read from the engineering session (host not
--   allowed), and no first-party page fetch exists that a person has reviewed: two stored Firecrawl snapshots of "https://info@newgen.edu.au"
--   (evidence 505c0c81, 31 Aug 2026; dccffc24, 11 Sep 2026; 37 kB and 40 kB, unreviewed) show the host answered but are not verification.
-- Changes: one pipeline.provider_website_checks row (action 'check') and one pipeline.admin_control_events row. No catalogue record changes.
-- Count guards: exactly one provider as measured; no check already running for it. All or nothing.
begin;
do $$
declare v_pid uuid := '2db6cb5e-eb25-4722-bac9-69c49166bdd7'; v_admin uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b'; v_n int; v_id uuid;
begin
  select count(*) into v_n from catalogue.providers p
   where p.id = v_pid and p.website = 'https://info@newgen.edu.au' and p.stable_key = 'provider:cricos:03871f' and p.lifecycle_status = 'active'
     and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos' and r.registration_code = '03871F' and r.status = 'active');
  if v_n <> 1 then raise exception 'NEWGEN step A guard: % providers as measured (expected 1); nothing changed', v_n; end if;
  if exists (select 1 from pipeline.provider_website_checks c where c.provider_id = v_pid and c.state <> 'done') then
    raise exception 'NEWGEN step A guard: a website check is already running for this provider; nothing changed'; end if;
  if (select count(*) from security.user_roles ur join security.roles r on r.code = ur.role_code where ur.user_id = v_admin and r.code = 'platform_admin' and r.status = 'active') <> 1 then
    raise exception 'NEWGEN step A guard: the requesting Platform Admin account is not active'; end if;
  insert into pipeline.provider_website_checks(provider_id, url, action, reason, requested_by)
  values (v_pid, 'https://newgen.edu.au/', 'check',
          'NEWGEN 03871F evidence check (ops G step A): candidate from Study Australia and Study Melbourne provider records (CRICOS 03871F, href https://newgen.edu.au/); verify CRICOS code on the home page. Not from the email address.',
          v_admin)
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'website_check_asked', v_pid::text, jsonb_build_object('check_id', v_id, 'url', 'https://newgen.edu.au/', 'change', 'CF-247 ops G NEWGEN step A',
          'provenance', jsonb_build_array(
            jsonb_build_object('kind', 'register_derived', 'publisher', 'Study Australia (Australian Government)', 'url', 'https://search.studyaustralia.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178',
                               'fields', jsonb_build_object('name', 'PHOENIX COLLEGE OF AUSTRALIA PTY LTD', 'cricos', '03871F', 'website', 'https://newgen.edu.au/', 'type', 'RTO'), 'read_at', '2026-11-03T15:58:00+11:00'),
            jsonb_build_object('kind', 'register_derived', 'publisher', 'Study Melbourne (State Government of Victoria)', 'url', 'https://coursesearch.studymelbourne.vic.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178',
                               'fields', jsonb_build_object('name', 'PHOENIX COLLEGE OF AUSTRALIA PTY LTD', 'cricos', '03871F', 'website', 'https://newgen.edu.au/'), 'read_at', '2026-11-03T16:00:00+11:00'),
            jsonb_build_object('kind', 'register', 'ref', 'catalogue.provider_registrations:d8e28854-ab9b-4245-93d8-088c465c4d13', 'source', 'b5680d74-49c5-49a5-b198-a625f3e3fdcf'))),
          v_admin);
  perform security.provider_website_check_kick_v1();
  raise notice 'NEWGEN step A: website check % queued for https://newgen.edu.au/ (it never saves a website). Read its verdict, then run step B only if it is verified.', v_id;
end $$;
commit;
-- Read the result (a few minutes later):
-- select id, state, verdict, why, result->>'final_url' final_url, result->>'redirected' redirected, result->>'http' http, result->>'title' title,
--        result->>'cricos_on_site' cricos_on_site, result->>'cricos_code' cricos_code, checked_at
--   from pipeline.provider_website_checks where provider_id = '2db6cb5e-eb25-4722-bac9-69c49166bdd7' order by requested_at desc limit 1;
