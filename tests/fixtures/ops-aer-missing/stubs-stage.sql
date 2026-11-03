-- shapes the priority edit and the staged status read (live columns; semantics reduced to what the cases need)
alter table catalogue.providers add column if not exists stable_key text;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('pipeline', 'aer.schedule_countries', 'Entry reading: countries', 'list', '["AU", "NZ"]'), ('pipeline', 'aer.schedule_countries_off', 'off', 'list', '[]'),
  ('pipeline', 'aer.schedule_lock_fields', 'locks', 'list', '["entry_requirements", "all"]')
on conflict do nothing;
alter table pipeline.evidence_artifacts add column if not exists storage_path text;
alter table catalogue.courses add column if not exists stable_key text;
create table if not exists pipeline.coverage_course_pages(course_id uuid, status text, evidence_id uuid, identity_basis text);
create table if not exists pipeline.manual_locks(entity text, entity_id uuid, field text);
create or replace function security.coverage_identity_allowed(p uuid, b text, f text) returns boolean language sql stable as $f$ select true $f$;
-- the Layer 4 gates, reduced: a matrix run is complete when it dropped nothing; a course read when its item says so
create or replace function security.entry_matrix_gate_v1(p_run uuid, p_exclude uuid[]) returns jsonb language sql stable as $f$
  select jsonb_build_object('complete', coalesce(r.rows_dropped, 0) = 0, 'reasons', case when coalesce(r.rows_dropped, 0) > 0 then jsonb_build_array('the reader dropped ' || r.rows_dropped || ' published row(s)') else '[]'::jsonb end)
    from pipeline.entry_matrix_runs r where r.id = p_run $f$;
create or replace function security.course_entry_gate_v1(p_item uuid, p_exclude uuid[] default '{}') returns jsonb language sql stable as $f$
  select jsonb_build_object('complete', coalesce((li.layer3_state->>'complete')::boolean, true), 'reasons', coalesce(li.layer3_state->'reasons', '[]'::jsonb))
    from pipeline.layer4_review_items li where li.id = p_item $f$;
-- the website projection, reduced to the keys read: active matrix rows of a published provider; a course's entry when it has an active row
create or replace function public.website_v2_provider(p text) returns jsonb language sql stable as $f$
  select jsonb_build_object('item', jsonb_build_object('entry_matrix', coalesce((select jsonb_agg(m.country_code) from catalogue.provider_entry_matrix m where m.provider_id = p2.id and m.status = 'active'), '[]'::jsonb)))
    from catalogue.providers p2 where p2.stable_key = p $f$;
create or replace function public.website_v2_course(p text) returns jsonb language sql stable as $f$
  select jsonb_build_object('item', jsonb_build_object('entry', jsonb_build_object('min_score', (select max(x.min_entry_score) from catalogue.course_entry_requirements x where x.course_id = c.id and x.status = 'active'), 'prerequisites', '[]'::jsonb)))
    from catalogue.courses c where c.stable_key = p $f$;
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values
  ('pipeline', 'entry.render_hosts', 'Entry matrices: sites read rendered', 'list', '["wgtn.ac.nz", "whitireiaweltec.ac.nz", "newcastle.edu.au", "griffith.edu.au"]')
on conflict do nothing;
create table if not exists pipeline.coverage_vendor_usage(id bigserial primary key, acquisition_provider_id uuid, units numeric, purpose text, provider_id uuid, url text,
  at timestamptz default now(), on_demand_run uuid);
