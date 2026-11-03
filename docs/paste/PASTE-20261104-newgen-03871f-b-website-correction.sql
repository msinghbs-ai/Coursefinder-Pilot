-- CF-247 ops workstream G, NEWGEN EDUCATION (CRICOS 03871F), step B of 2: the provenance-backed website correction. PASTE FILE. Not applied by
-- any migration. Run by the Integration Controller through governance, ONLY after step A's check has finished.
-- It refuses (nothing changes) unless the platform's own website check from step A read the site and found CRICOS provider code 03871F on its
-- home page (verdict 'verified', cricos_on_site true, cricos_code 03871F), within 7 days, with the final address (after redirects) on newgen.edu.au.
-- If it refuses, the provider stays blocked: onboarding d5dfc2ea stays stopped needs_source_discovery, and the identity investigation (ops G,
-- pipeline.provider_identity_investigations, once 20261104060000 is deployed) holds the evidence in state blocked_evidence.
-- How it corrects: through the existing authorised website-change path, security.provider_website_change_apply_v1 (md5 cf7fbf19...), which saves
--   the website as entered by the Platform Admin (public.admin_provider_website_set: logged, locked against overwrite), moves the generic course
--   link recipe to the new domain, queues the course-page searches that found nothing, and logs admin_control_events 'website_change'. The change
--   row carries the step A check's verdict and page fetch, and this file's provenance.
-- Evidence carried (see step A for the full list): Study Australia and Study Melbourne provider records for CRICOS 03871F with href
--   https://newgen.edu.au/; the platform's register record d8e28854 (cricos 03871F, active); the step A page fetch (final URL, redirect, title,
--   CRICOS code on the page).
-- Count guards: exactly one provider still as measured; exactly one verified step A check; no other active provider on newgen.edu.au; the two
--   functions it calls are the definitions this file was written against. Exactly one provider row changes. All or nothing.
-- Rollback: PASTE-20261104-newgen-03871f-b-website-correction-rollback.sql.
begin;
do $$
declare v_pid uuid := '2db6cb5e-eb25-4722-bac9-69c49166bdd7'; v_admin uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';
        v_n int; c pipeline.provider_website_checks; v_id uuid; v_note jsonb; v_site text; v_host text;
begin
  if md5(pg_get_functiondef('security.provider_website_change_apply_v1(uuid)'::regprocedure)) <> 'cf7fbf191d127d896c34af965163ea30'
     or md5(pg_get_functiondef('public.admin_provider_website_set(uuid,text)'::regprocedure)) <> '7de75fd98eb315284f59ed306b9e3822' then
    raise exception 'NEWGEN step B guard: the website-change path differs from the one this file was written against; nothing changed'; end if;
  select count(*) into v_n from catalogue.providers p
   where p.id = v_pid and p.website = 'https://info@newgen.edu.au' and p.stable_key = 'provider:cricos:03871f' and p.lifecycle_status = 'active'
     and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos' and r.registration_code = '03871F' and r.status = 'active');
  if v_n <> 1 then raise exception 'NEWGEN step B guard: % providers as measured (expected 1); nothing changed', v_n; end if;
  select count(*) into v_n from pipeline.provider_website_checks x
   where x.provider_id = v_pid and x.action = 'check' and x.state = 'done' and x.reason like 'NEWGEN 03871F evidence check (ops G step A)%'
     and x.checked_at >= now() - interval '7 days'  -- fixed: a one-off paste; the page fetch it relies on must be this week's
     and x.verdict = 'verified' and coalesce((x.result->>'cricos_on_site')::boolean, false) and upper(coalesce(x.result->>'cricos_code', '')) = '03871F'
     and coalesce((x.result->>'third_party')::boolean, false) = false
     and lower(regexp_replace(substring(coalesce(nullif(x.result->>'final_url', ''), x.url) from '^https?://([^/:?#]+)'), '^www\.', '')) = 'newgen.edu.au';
  if v_n <> 1 then
    raise exception 'NEWGEN step B guard: % verified step A checks (expected 1: CRICOS 03871F on the home page of newgen.edu.au within 7 days). Not verified: the provider stays blocked; nothing changed', v_n;
  end if;
  select * into c from pipeline.provider_website_checks x
   where x.provider_id = v_pid and x.action = 'check' and x.state = 'done' and x.verdict = 'verified' and x.reason like 'NEWGEN 03871F evidence check (ops G step A)%'
   order by x.checked_at desc limit 1;
  v_site := regexp_replace(coalesce(nullif(c.result->>'final_url', ''), c.url), '^(https?://[^/?#]+).*$', '\1');
  v_host := lower(regexp_replace(substring(v_site from '^https?://([^/:?#]+)'), '^www\.', ''));
  select count(*) into v_n from catalogue.providers p
   where p.id <> v_pid and p.lifecycle_status = 'active' and regexp_replace(security.site_host_v1(p.website), '^.*@', '') = v_host;
  if v_n <> 0 then raise exception 'NEWGEN step B guard: % other active providers already have %; nothing changed', v_n, v_host; end if;
  -- the change row: the verified page fetch and its provenance, applied through the existing path
  insert into pipeline.provider_website_checks(provider_id, url, action, reason, requested_by, state, result, verdict, why, checked_at)
  values (v_pid, v_site, 'change',
          left('NEWGEN 03871F correction (ops G step B): register-derived records (Study Australia, Study Melbourne: CRICOS 03871F -> https://newgen.edu.au/) and the platform site check '
               || c.id || ' (' || c.why || '; final ' || coalesce(c.result->>'final_url', c.url) || ', redirected ' || coalesce(c.result->>'redirected', 'false') || '). Replaces the malformed register value https://info@newgen.edu.au.', 500),
          v_admin, 'done', c.result, c.verdict, c.why, c.checked_at)
  returning id into v_id;
  v_note := security.provider_website_change_apply_v1(v_id);
  if v_note is null then raise exception 'NEWGEN step B: the website-change path did not apply; nothing changed'; end if;
  select count(*) into v_n from catalogue.providers p where p.id = v_pid and security.website_refusal_v1(p.website) is null
     and lower(regexp_replace(substring(p.website from '^https?://([^/:?#]+)'), '^www\.', '')) = v_host;
  if v_n <> 1 then raise exception 'NEWGEN step B post-check: the website is not % after the change; rolled back', v_host; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'website_correction_provenance', v_pid::text, jsonb_build_object('change', 'CF-247 ops G NEWGEN step B', 'change_check_id', v_id, 'verified_check_id', c.id,
          'before', 'https://info@newgen.edu.au', 'after', v_site, 'page_fetch', c.result - 'worker', 'applied', v_note,
          'register_derived', jsonb_build_array('https://search.studyaustralia.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178',
                                                'https://coursesearch.studymelbourne.vic.gov.au/provider/phoenix-college-of-australia-pty-ltd/7c857632a71b4e82d4a36ff0e52b4178'),
          'register', 'catalogue.provider_registrations:d8e28854-ab9b-4245-93d8-088c465c4d13'), v_admin);
  raise notice 'NEWGEN step B: website corrected to % (check %, change %); onboarding carries on by itself on its next run', v_site, c.id, v_id;
end $$;
commit;
