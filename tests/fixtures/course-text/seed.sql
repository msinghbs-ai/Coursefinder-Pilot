-- the live rows this change reads or updates (3 Nov 2026): the field register's two rows and its neighbours, the starting source rules,
-- the page proofs of AU, NZ and CA, the provider description settings it reuses, and the standing queue switched on
insert into ref.countries(id, iso_alpha2, name) values ('00000000-0000-0000-0000-0000000000a1', 'AU', 'Australia'), ('00000000-0000-0000-0000-0000000000a2', 'NZ', 'New Zealand'),
  ('00000000-0000-0000-0000-0000000000a3', 'CA', 'Canada');
insert into pipeline.field_register(field, level, label, grp, sort, reader, fills, target_pct, active, reason, updated_at) values
 ('intakes', 'course', 'Intakes / start dates', 'Dates', 110, 'coverage', 'Adapters, central calendars, page reader (coverage pipeline)', 80, true, 'CF-247 21 Oct 2026: starting register', now()),
 ('deadline', 'course', 'Application deadline', 'Dates', 120, 'none', 'No reader yet (next release)', 80, true, 'CF-247 21 Oct 2026: starting register', now()),
 ('description', 'course', 'Course description', 'Course page', 150, 'none', 'No reader yet (next release)', 80, true, 'CF-247 21 Oct 2026: starting register', now()),
 ('p_description', 'provider', 'Description', 'Provider', 290, 'none', 'No reader yet (next release)', 80, true, 'CF-247 21 Oct 2026: starting register', now());
insert into pipeline.field_source_rules(country_code, field, sources, reason, updated_at) values
 ('ALL', 'intakes', array['ai_stored'], 'CF-247 23 Oct 2026 (Platform Admin 10:25): the AI reader reads the start months from the stored course page', now());
insert into pipeline.coverage_admission_countries(country_id, active, identities, updated_at) values
 ('00000000-0000-0000-0000-0000000000a1', true, '{"english":["adapter_code","adapter_title","cricos_code","exact_title","host_page","manual"],"intakes":["adapter_code","adapter_title","cricos_code","exact_title","host_page","manual"],"tuition":["cricos_code","adapter_code","manual"],"official_url":["adapter_code","adapter_title","cricos_code","exact_title","host_page","manual"],"entry_requirements":["cricos_code","adapter_code","manual"]}', now()),
 ('00000000-0000-0000-0000-0000000000a3', true, '{"english":["adapter_code","adapter_title","exact_title","field_award","host_page","manual"],"intakes":["adapter_code","adapter_title","exact_title","field_award","host_page","manual"],"tuition":["exact_title","field_award","manual"],"official_url":["adapter_code","adapter_title","exact_title","field_award","host_page","manual"]}', now()),
 ('00000000-0000-0000-0000-0000000000a2', true, '{"english":["adapter_code","adapter_title","degree_name","exact_title","host_page","manual","nzqa_code","title_level"],"intakes":["adapter_code","adapter_title","degree_name","exact_title","host_page","manual","nzqa_code","title_level"],"tuition":["adapter_title","exact_title","manual","nzqa_code","title_level"],"official_url":["adapter_code","adapter_title","degree_name","exact_title","host_page","manual","nzqa_code","title_level"],"entry_requirements":["nzqa_code","adapter_code","manual"]}', now());
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'pdesc.superlatives', 's', 'h', 'list', '["best","leading","world-class","world class","world-leading","top","premier","renowned","prestigious","excellent","excellence","outstanding","unrivalled","unparalleled","finest","elite","cutting-edge","award-winning","number one","#1","first-class","exceptional","innovative","vibrant"]', null, null, 'words', 981, 'Provider descriptions', 'security.provider_description_validate_v1'),
 ('pipeline', 'pdesc.claim_words', 'c', 'h', 'list', '["ranked","ranking","rankings","rated","rating","qs","times higher","top 1%","employment","employability","employed","employers","graduate outcomes","salary","salaries","accredited","accreditation","facilities","state-of-the-art","five-star","5-star","students","staff","alumni","award","awards"]', null, null, 'words', 982, 'Provider descriptions', 'security.provider_description_validate_v1'),
 ('pipeline', 'pdesc.support_min_share', 'm', 'h', 'number', '0.6', 0.3, 1, 'share', 977, 'Provider descriptions', 'security.provider_description_validate_v1'),
 ('pipeline', 'pdesc.duplicate_share', 'd', 'h', 'number', '0.8', 0.5, 1, 'share', 978, 'Provider descriptions', 'security.provider_description_validate_v1'),
 ('pipeline', 'intake_dates.deadline_max_days_before', 'x', 'h', 'number', '366', 30, 730, 'days', 1, 'Intake dates', 'security.intake_dates_plan_v1'),
 ('pipeline', 'gaps.recheck_days', 'r', 'h', 'number', '60', 7, 365, 'days', 104, 'Re-read and retry', 'security.field_gap_queue_tick_v1');
insert into pipeline.field_gap_queue_control values (1, true, null, 'standing');
insert into pipeline.central_ai_settings values (1, 'openai/gpt-4.1-mini', 'mini');
insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.enrich_fields_v1', 'Enrichment', 'Enrich fields list', 'active', 'x'), ('function', 'public.svc_enrich_ai_record', 'Enrichment', 'record', 'active', 'x');
