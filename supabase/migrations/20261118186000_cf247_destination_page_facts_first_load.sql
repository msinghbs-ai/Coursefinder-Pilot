-- CF-247 RM1I / RM1C / RM1H / RM1D: the first page-facts load (S2-Build; Platform Admin 18 Nov 2026 15:32: "Build and run the page-facts loader").
-- Pilot #1291 (migration 20261118185000) built destination.page_facts, the load and job destination-page-facts-load, and deployed
-- layer1-destination-geo-loader v1.2.0 (mode facts) after its migration had applied. This change asks for the first load through Run now,
-- as the Platform Admin who gave the direction; the hourly target destination-open-licence-publish then approves the drafts that carry
-- evidence and a verbatim quote (owners on destination.open_licence_owners, terms approved) and publishes their editions.
-- Nothing else changes. Nothing is dropped or deleted. G3 untouched.
-- Replaces: nothing.
-- Retires: nothing.

do $r$
declare v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin who gave the direction (15:32)
        v_run jsonb;
begin
  if not exists (select 1 from pg_proc where oid = 'security.destination_page_facts_load_v1(jsonb)'::regprocedure) then
    raise exception 'the page-facts load (20261118185000) is not applied';
  end if;
  if position('destination-page-facts-load' in (select prosrc from pg_proc where oid = 'security.destination_job_run_now_v1(text,text,jsonb,uuid)'::regprocedure)) = 0 then
    raise exception 'Run now does not know destination-page-facts-load';
  end if;
  v_run := security.destination_job_run_now_v1('destination-page-facts-load', 'Platform Admin 18 Nov 2026 15:32: run the page-facts loader (first load after v1.2.0 deployed)',
                                               jsonb_build_object('idempotency_key', 'cf247-20261118186000-page-facts-first-load'), v_admin);
  raise notice 'page-facts load asked for: %', v_run;
end $r$;
