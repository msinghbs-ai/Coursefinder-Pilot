-- The circular gate, on the live definitions (before 20261107150000): all of these providers are AER-eligible and in a country that is on, yet none can be given a first page.
do $$
begin
  perform fx.ok(security.aer_schedule_active_v1(), 'B0 the scheduled reading is on');
  perform fx.ok(not security.entry_matrix_enabled_v1('d1000000-0000-4000-8000-0000000000b3'), 'B1 a provider with no entry page is not "enabled"');
  perform fx.ok(security.entry_matrix_attach_v1() = 0, 'B2 the attach cannot give it a suggested first page');
  perform fx.ok((select count(*) from pipeline.entry_matrix_sources where provider_id = 'd1000000-0000-4000-8000-0000000000b3') = 0, 'B3 nothing attached');
  raise notice 'B circular gate reproduced on live definitions: a suggested first page is never attached';
end $$;
