-- CF-247 AER missing-university strategy, workstream C: ROLLBACK of PASTE-20261104-aer-missing-university-sources.sql.
-- Removes exactly the 4 sources it attached, and only while none of them has been read (no run, no stored copy): once a page has been read its
-- run, rows and Layer 4 item are history and the source stays (hold it instead). PASTE FILE; not applied by any migration. Deletes exactly 4 rows.
begin;
do $$
declare v_n int;
begin
  create temporary table att(provider_id uuid, url text) on commit drop;
  insert into att values
    ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2', 'https://www.cdu.edu.au/international/how-apply/entry-requirements'),
    ('551383f9-7732-4588-a843-dd2b97c13f6f', 'https://www.unisq.edu.au/international/apply/entry-requirements'),
    ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2', 'https://www.une.edu.au/international/apply/eligibility/academic-requirements'),
    ('fec52f92-a8a3-4de8-a862-06f355e4e2f7', 'https://www.torrens.edu.au/apply-online/admissions-criteria');
  select count(*) into v_n from pipeline.entry_matrix_sources s join att a on a.provider_id = s.provider_id and a.url = s.url
   where s.found_via = 'manual' and s.read_at is null and s.content_hash is null and not exists (select 1 from pipeline.entry_matrix_runs r where r.source_id = s.id);
  if v_n <> 4 then raise exception 'rollback guard: % of 4 sources are unread; nothing changed (hold read sources instead)', v_n; end if;
  delete from pipeline.entry_matrix_sources s using att a where a.provider_id = s.provider_id and a.url = s.url and s.read_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 4 then raise exception 'rollback guard: deleted %, expected 4; rolled back', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('entry_requirements', 'aer_missing_university_sources_rollback', 'pipeline.entry_matrix_sources', jsonb_build_object('count', 4));
end $$;
commit;
