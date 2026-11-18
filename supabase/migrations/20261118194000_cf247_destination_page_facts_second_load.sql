-- CF-247 RM1I / RM1C / RM1H / RM1D: the second page-facts load (S2-Build; Platform Admin 18 Nov 2026 15:32: "Build and run the page-facts loader").
-- The first load (20261118186000, run 1e3b285f) read and stored both Home Affairs pages but found no fact: the text reader of v1.2.0 swallowed
-- the page after a self-closing tag, and the JSA workbook link was not recognised. Pilot #1294 (20261118191000) deployed v1.2.1 with both
-- fixed. This change asks for the load again through Run now, as the Platform Admin who gave the direction; the hourly target
-- destination-open-licence-publish then approves the drafts that carry evidence and a verbatim quote and publishes their editions.
-- Nothing else changes. Nothing is dropped or deleted. G3 untouched.
-- Replaces: nothing.
-- Retires: nothing.

do $r$
declare v_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';  -- the Platform Admin who gave the direction (15:32)
        v_run jsonb;
begin
  if position('page_text_length' in (select prosrc from pg_proc where oid = 'security.destination_page_facts_load_v1(jsonb)'::regprocedure)) = 0 then
    raise exception 'the page-facts reader fix (20261118191000) is not applied';
  end if;
  v_run := security.destination_job_run_now_v1('destination-page-facts-load', 'Platform Admin 18 Nov 2026 15:32: run the page-facts loader again after the v1.2.1 reader fix',
                                               jsonb_build_object('idempotency_key', 'cf247-20261118194000-page-facts-second-load'), v_admin);
  raise notice 'page-facts load asked for: %', v_run;
end $r$;
