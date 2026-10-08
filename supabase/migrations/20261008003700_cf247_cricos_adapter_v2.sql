-- CF-247 Phase 2 (8 Oct 2026, Platform Admin: "Extend CRICOS, then switch"): the CRICOS register adapter (au_cricos) becomes version 2 so
-- a Layer 1 worker can take everything it applies from it: the provider's postal address (city, state, address lines, postcode, read with
-- the same column fallbacks as layer1-au-depth), the campus locations of the selected providers and the locations of each selected course
-- (as row sets). The plan fingerprints are unchanged. layer1-au-depth v1.8.0 and layer1-au-cricos-facts v1.3.0 read with it once it is
-- switched on. Because the spec changed, the three stored archives are replayed again (coverage-sweep v0.17.25 also compares the address
-- fields and both location sets); switching on stays a separate Platform Admin step that needs a passing replay of this version.
update pipeline.register_adapters
   set spec = spec || jsonb_build_object('fields', (spec->'fields') || '{"provider_city": {"from": "provider", "columns": ["Postal Address City", "Postal City"]}, "provider_state": {"from": "provider", "columns": ["Postal Address State", "Postal State", "State"]}, "provider_address_line1": {"from": "provider", "columns": ["Postal Address Line 1", "Postal Address 1"]}, "provider_address_line2": {"from": "provider", "join_columns": [["Postal Address Line 2", "Postal Address 2"], ["Postal Address Line 3", "Postal Address 3"], ["Postal Address Line 4", "Postal Address 4"]], "sep": ", "}, "provider_postcode": {"from": "provider", "columns": ["Postal Address Postcode", "Postal Postcode", "Postcode"]}}'::jsonb,
                                         'record_provider', 'CRICOS Provider Code',
                                         'sets', '{"locations": {"file": "locations", "prefix": "loc", "filter": {"column": "CRICOS Provider Code", "in": "record_providers"}, "fields": {"provider_code": "CRICOS Provider Code", "location_code": "Location Name", "location_name": "Location Name", "address_line1": "Address Line 1", "address_line2": {"join_columns": [["Address Line 2"], ["Address Line 3"], ["Address Line 4"]], "sep": ", "}, "city": "City", "state": "State", "postcode": "Postcode"}, "require": ["provider_code", "location_code"], "key": ["provider_code", "location_code"]}, "course_locations": {"file": "course_locations", "prefix": "cl", "filter": {"column": "CRICOS Course Code", "in": "record_keys"}, "fields": {"provider_code": {"column": "CRICOS Provider Code", "fallback": "record_provider"}, "course_code": "CRICOS Course Code", "location_code": "Location Name"}, "constants": {"delivery_mode": "on_campus"}, "require": ["provider_code", "location_code"], "dedupe": ["provider_code", "course_code", "location_code"], "key": ["provider_code", "course_code", "location_code"]}}'::jsonb),
       version = 2, updated_at = now(),
       notes = 'Phase 2 register adapter, version 2 (provider address and location sets). Not switched on until a replay of version 2 passes and a Platform Admin switches it.'
 where code = 'au_cricos' and version = 1 and not switched_on;

insert into pipeline.register_replay_runs(source_id, label, storage_path, zip_hash, keep_fields, created_at)
select r.source_id, r.label || ' (v2)', r.storage_path, r.zip_hash, false, now() + make_interval(secs => x.n)
  from (values ('CRICOS 11 Aug 2026', 0), ('CRICOS 26 Sep 2026', 1), ('CRICOS 30 Sep 2026 (newest)', 2)) x(label, n)
  join pipeline.register_replay_runs r on r.label = x.label;
