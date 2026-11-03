-- CF-247 ops workstream G, NEWGEN EDUCATION (CRICOS 03871F): rollback of step B. PASTE FILE. Puts the recorded website back to the value before
-- step B ("https://info@newgen.edu.au"), through the same entry path (public.admin_provider_website_set as the Platform Admin, logged). The
-- onboarding website check (onboarding.website_check_on) then stops onboarding again with needs_source_discovery. The course link recipe and the
-- course-page searches queued by step B are left as they are (they only find pages the reader proves). Nothing is deleted.
-- Count guard: exactly one step B change applied for this provider, and the website is still the one step B saved.
begin;
do $$
declare v_pid uuid := '2db6cb5e-eb25-4722-bac9-69c49166bdd7'; v_admin uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b'; v_n int; v_saved text;
begin
  select count(*), max(x.apply_note->>'saved') into v_n, v_saved from pipeline.provider_website_checks x
   where x.provider_id = v_pid and x.action = 'change' and x.applied and x.reason like 'NEWGEN 03871F correction (ops G step B)%';
  if v_n <> 1 then raise exception 'NEWGEN rollback guard: % step B changes (expected 1); nothing changed', v_n; end if;
  if (select website from catalogue.providers where id = v_pid) is distinct from v_saved then
    raise exception 'NEWGEN rollback guard: the website has changed since step B; nothing changed'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  perform public.admin_provider_website_set(v_pid, 'https://info@newgen.edu.au');
  perform set_config('request.jwt.claims', '', true);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('provider', 'website_correction_rollback', v_pid::text, jsonb_build_object('change', 'CF-247 ops G NEWGEN step B rollback', 'from', v_saved, 'to', 'https://info@newgen.edu.au'), v_admin);
  raise notice 'NEWGEN step B rolled back: website % -> https://info@newgen.edu.au', v_saved;
end $$;
commit;
