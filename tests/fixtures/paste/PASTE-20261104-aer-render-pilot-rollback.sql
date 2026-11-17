-- CF-247 AER missing-university rendered pilot: ROLLBACK of PASTE-20261104-aer-render-pilot.sql. Restores entry.render_hosts to the four hosts
-- exactly; removes the JCU selector source only while it is unread (once read, its run and Layer 4 item are history and the source stays).
-- PASTE FILE; not applied by any migration. Changes one setting; deletes at most 1 row.
begin;
do $$
declare v_now jsonb := (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'entry.render_hosts'); v_n int := 0;
begin
  if v_now is distinct from '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au", "jcu.edu.au", "unisq.edu.au"]'::jsonb then
    raise exception 'rollback guard: entry.render_hosts is % (not the pilot value); nothing changed', v_now; end if;
  update pipeline.platform_toolset_settings set value = '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au"]'::jsonb, updated_at = now(),
         reason = 'CF-247 AER missing-university rendered pilot ended (rollback)'
   where toolset_key = 'pipeline' and key = 'entry.render_hosts';
  delete from pipeline.entry_matrix_sources s
   where s.provider_id = 'fe6af182-f5ca-4a3c-bfb4-b0773ff1b113' and s.read_at is null and s.content_hash is null
     and s.url = 'https://www.jcu.edu.au/entry-options/entry-requirements/academic-and-english-language-entry-requirements/country-specific-academic-levels'
     and not exists (select 1 from pipeline.entry_matrix_runs r where r.source_id = s.id);
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('entry_requirements', 'aer_render_pilot_rollback', 'pipeline.platform_toolset_settings:entry.render_hosts', jsonb_build_object('jcu_source_removed', v_n));
end $$;
commit;
