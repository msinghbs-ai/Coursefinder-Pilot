-- after the paste file: the sources are the inventory's exact URLs; classes move to read_held/awaiting once read; verify waits for the read
do $$
begin
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources s join pipeline.aer_source_inventory i on i.provider_id = s.provider_id and i.url = s.url and i.attach) = 4, 'P1 the 4 attached are the inventory URLs');
  perform fx.ok((security.aer_source_inventory_verify_v1(0)->'measure'->>'attached')::int = 4 and not (security.aer_source_inventory_verify_v1(0)->>'passed')::boolean, 'P1 verify: attached, not yet read');
  perform fx.ok(security.aer_source_class_v1('6f5cb7f7-7c70-4c06-970f-f368c3a786e2') = 'source_found', 'P1 attached, not yet read: source_found until the AER reconcile sees the read');
  perform fx.ok((select count(*) from pipeline.admin_control_events where action = 'aer_missing_university_sources') = 1, 'P1 recorded once');
  raise notice 'P1 paste file: the 4 inventory URLs attached, recorded; verify passes only once they are read';
end $$;
