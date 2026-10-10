-- CF-247 Phase 2 (8 Oct 2026, Platform Admin, multiple choice "Start building Phase 2"): CRICOS becomes the first register adapter.
-- The register is described as data (pipeline.register_adapters.spec): the files in the archive, the record file and key, the active rule,
-- the joins, the fingerprint parts and the field mapping. Nothing is switched: the CRICOS adapter is stored with switched_on = false and
-- Layer 1 (layer1-au-depth, layer1-au-cricos-facts and their run plans) keeps running unchanged.
-- Side-by-side replay: for each stored register archive (the last three: 11 Aug, 26 Sep, 30 Sep 2026) the coverage-sweep worker
-- (mode register_replay, v0.17.19) reads the archive twice, once with the adapter spec and once with a verbatim copy of today's Layer 1
-- code, and saves one row per course for each. security.register_replay_compare_v1 compares them row by row (keys, fingerprints, fields)
-- and, for the newest archive, also against the fingerprints Layer 1 recorded (layer1_register_row_state) and the catalogue.
-- Pass criteria for the gate (recorded in the result): every archive has identical keys, fingerprints and fields under both engines;
-- the newest archive's fingerprints equal Layer 1's recorded ones for every course seen in that run. A pass does not switch anything.
create table if not exists pipeline.register_adapters (
  source_id uuid primary key, code text not null unique, label text not null, country_code text not null, spec jsonb not null,
  version int not null default 1, switched_on boolean not null default false, notes text, updated_by uuid, updated_at timestamptz not null default now());
alter table pipeline.register_adapters enable row level security;
revoke all on pipeline.register_adapters from public, anon, authenticated;

create table if not exists pipeline.register_replay_runs (
  id uuid primary key default gen_random_uuid(), source_id uuid not null, label text not null, storage_path text not null, zip_hash text,
  keep_fields boolean not null default false, reference_done boolean not null default false, adapter_done boolean not null default false,
  reference_records int, adapter_records int, error text, result jsonb, created_at timestamptz not null default now(), done_at timestamptz);
create table if not exists pipeline.register_replay_keys (
  run_id uuid not null references pipeline.register_replay_runs(id), engine text not null check (engine in ('reference', 'adapter')),
  record_key text not null, fingerprint text not null, fields_hash text not null, fields jsonb, dup int not null default 0,
  primary key (run_id, engine, record_key));
alter table pipeline.register_replay_runs enable row level security;
alter table pipeline.register_replay_keys enable row level security;
revoke all on pipeline.register_replay_runs, pipeline.register_replay_keys from public, anon, authenticated;

insert into pipeline.register_adapters(source_id, code, label, country_code, spec, notes)
values ('b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'au_cricos', 'CRICOS Providers, Courses and Locations', 'AU', '{"format": "zip_csv", "files": {"institutions": {"name_regex": "institutions.*\\.csv$"}, "courses": {"name_regex": "courses.*\\.csv$", "not_regex": "course locations"}, "locations": {"name_regex": "locations.*\\.csv$", "not_regex": "course locations"}, "course_locations": {"name_regex": "course locations.*\\.csv$"}}, "record": {"file": "courses", "key": "CRICOS Course Code", "active": {"column": "Expired", "active_if_empty_or": "^(no|false|n|0)$"}}, "joins": [{"as": "provider", "file": "institutions", "on": [["CRICOS Provider Code", "CRICOS Provider Code"]]}, {"as": "locations", "file": "course_locations", "on": [["CRICOS Course Code", "CRICOS Course Code"]], "many": true, "then": {"file": "locations", "on": [["CRICOS Provider Code", "CRICOS Provider Code"], ["Location Name", "Location Name"]]}}], "fingerprint": {"parts": ["record", "join:provider", "many:locations"], "field_sep": "\u001f", "part_sep": "\u001d", "pair_sep": "\u001e"}, "fields": {"provider_code": "CRICOS Provider Code", "course_code": "CRICOS Course Code", "course_name": "Course Name", "course_level_raw": "Course Level", "duration_weeks": "Duration (Weeks)", "field_code": {"column": "Field of Education 1 Narrow Field", "split": "asced4", "part": "code"}, "field_name": {"column": "Field of Education 1 Narrow Field", "split": "asced4", "part": "name"}, "vet_national_code": "VET National Code", "dual_qualification": "Dual Qualification", "secondary_field_code": {"column": "Field of Education 2 Narrow Field", "split": "asced4", "part": "code"}, "secondary_field_name": {"column": "Field of Education 2 Narrow Field", "split": "asced4", "part": "name"}, "foundation_studies": "Foundation Studies", "work_component": "Work Component", "work_component_hours_per_week": {"column": "Work Component Hours/Week", "numeric_text": true}, "work_component_weeks": {"column": "Work Component Weeks", "numeric_text": true}, "work_component_total_hours": {"column": "Work Component Total Hours", "numeric_text": true}, "course_language": "Course Language", "tuition_fee": "Tuition Fee", "non_tuition_fee": "Non Tuition Fee", "estimated_total_course_cost": "Estimated Total Course Cost", "provider_name": {"from": "provider", "columns": ["Trading Name", "Institution Name"]}, "provider_website": {"from": "provider", "column": "Website", "prefix_https": true}}}'::jsonb,
        'Phase 2 register adapter. Archive from data.gov.au package cricos (ZIP named Providers, Courses and Locations). Not switched on: Layer 1 run plans stay in charge until the side-by-side replay passes and a Platform Admin switches it.')
on conflict (source_id) do nothing;

create or replace function public.svc_register_replay_next()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.register_replay_runs where done_at is null and error is null and not (reference_done and adapter_done) order by created_at limit 1;
  if r.id is null then return null; end if;
  return jsonb_build_object('run_id', r.id, 'engine', case when not r.reference_done then 'reference' else 'adapter' end, 'storage_path', r.storage_path,
                            'zip_hash', r.zip_hash, 'keep_fields', r.keep_fields, 'spec', (select a.spec from pipeline.register_adapters a where a.source_id = r.source_id));
end $f$;

create or replace function public.svc_register_replay_save(p_run_id uuid, p_engine text, p_rows jsonb, p_final boolean, p_error text default null)
returns int language plpgsql security definer set search_path = '' as $f$
declare n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if p_error is not null then
    update pipeline.register_replay_runs set error = p_engine || ': ' || left(p_error, 300), done_at = now() where id = p_run_id;
    return 0;
  end if;
  insert into pipeline.register_replay_keys(run_id, engine, record_key, fingerprint, fields_hash, fields)
  select p_run_id, p_engine, x->>'k', x->>'f', x->>'h', x->'x' from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x
  on conflict (run_id, engine, record_key) do update set fingerprint = excluded.fingerprint, fields_hash = excluded.fields_hash, fields = excluded.fields,
         dup = pipeline.register_replay_keys.dup + 1;
  get diagnostics n = row_count;
  if p_final then
    update pipeline.register_replay_runs
       set reference_done = reference_done or p_engine = 'reference', adapter_done = adapter_done or p_engine = 'adapter',
           reference_records = case when p_engine = 'reference' then (select count(*) from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'reference') else reference_records end,
           adapter_records = case when p_engine = 'adapter' then (select count(*) from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'adapter') else adapter_records end
     where id = p_run_id;
    perform security.register_replay_compare_v1(p_run_id);
  end if;
  return n;
end $f$;
revoke all on function public.svc_register_replay_next(), public.svc_register_replay_save(uuid, text, jsonb, boolean, text) from public, anon, authenticated;
grant execute on function public.svc_register_replay_next(), public.svc_register_replay_save(uuid, text, jsonb, boolean, text) to service_role;

create or replace function security.register_replay_compare_v1(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare r pipeline.register_replay_runs%rowtype; v jsonb; v_latest boolean; v_l1 jsonb := null; v_cat jsonb := null; v_seen timestamptz;
begin
  select * into r from pipeline.register_replay_runs where id = p_run_id;
  if not (r.reference_done and r.adapter_done) then return null; end if;
  with a as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'adapter'),
       b as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'reference')
  select jsonb_build_object(
    'reference_records', (select count(*) from b), 'adapter_records', (select count(*) from a),
    'only_reference', (select count(*) from b where not exists (select 1 from a where a.record_key = b.record_key)),
    'only_adapter', (select count(*) from a where not exists (select 1 from b where b.record_key = a.record_key)),
    'fingerprint_differs', (select count(*) from a join b using (record_key) where a.fingerprint <> b.fingerprint),
    'fields_differ', (select count(*) from a join b using (record_key) where a.fields_hash <> b.fields_hash),
    'duplicate_keys', (select count(*) from b where dup > 0),
    'sample_differs', (select coalesce(jsonb_agg(record_key), '[]'::jsonb) from (select a.record_key from a join b using (record_key) where a.fingerprint <> b.fingerprint or a.fields_hash <> b.fields_hash limit 10) s))
  into v;
  -- newest archive: also against what Layer 1 recorded and the catalogue
  v_latest := r.keep_fields;
  if v_latest then
    select max(seen_at) into v_seen from pipeline.layer1_register_row_state where source_id = r.source_id;
    with a as (select * from pipeline.register_replay_keys where run_id = p_run_id and engine = 'adapter'),
         s as (select * from pipeline.layer1_register_row_state where source_id = r.source_id and seen_at >= v_seen - interval '1 hour')
    select jsonb_build_object('layer1_seen', (select count(*) from s), 'matched', (select count(*) from a join s on s.record_key = a.record_key and s.fingerprint = a.fingerprint),
                              'fingerprint_differs', (select count(*) from a join s on s.record_key = a.record_key and s.fingerprint <> a.fingerprint),
                              'only_layer1', (select count(*) from s where not exists (select 1 from a where a.record_key = s.record_key)),
                              'only_adapter', (select count(*) from a where not exists (select 1 from s where s.record_key = a.record_key)))
      into v_l1;
    with a as (select k.record_key, k.fields from pipeline.register_replay_keys k where k.run_id = p_run_id and k.engine = 'adapter'),
         c as (select a.record_key, a.fields, co.id course_id, co.duration_value, co.duration_unit,
                      (select f.amount from catalogue.course_fees f where f.course_id = co.id and f.status = 'active' and f.fee_type = 'tuition' and f.basis = 'registered_total_course' order by f.created_at desc limit 1) tuition
                 from a join catalogue.course_registrations cr on lower(cr.scheme) = 'cricos' and upper(cr.registration_code) = upper(a.record_key)
                 join catalogue.courses co on co.id = cr.course_id)
    select jsonb_build_object('courses_matched', (select count(*) from c),
                              'duration_same', (select count(*) from c where c.duration_unit = 'weeks' and c.duration_value = nullif(c.fields->>'duration_weeks', '')::numeric),
                              'duration_differs', (select count(*) from c where nullif(c.fields->>'duration_weeks', '') ~ '^[0-9.]+$' and (c.duration_unit is distinct from 'weeks' or c.duration_value is distinct from (c.fields->>'duration_weeks')::numeric)),
                              'tuition_same', (select count(*) from c where c.tuition = nullif(regexp_replace(c.fields->>'tuition_fee', '[^0-9.]', '', 'g'), '')::numeric),
                              'tuition_differs', (select count(*) from c where nullif(regexp_replace(c.fields->>'tuition_fee', '[^0-9.]', '', 'g'), '')::numeric > 0 and c.tuition is distinct from regexp_replace(c.fields->>'tuition_fee', '[^0-9.]', '', 'g')::numeric))
      into v_cat;
  end if;
  v := v || jsonb_build_object('against_layer1_recorded', v_l1, 'against_catalogue', v_cat,
    'pass', (v->>'only_reference')::int = 0 and (v->>'only_adapter')::int = 0 and (v->>'fingerprint_differs')::int = 0 and (v->>'fields_differ')::int = 0
            and (v_l1 is null or ((v_l1->>'fingerprint_differs')::int = 0 and (v_l1->>'only_layer1')::int = 0 and (v_l1->>'only_adapter')::int = 0)));
  update pipeline.register_replay_runs set result = v, done_at = now() where id = p_run_id;
  return v;
end $f$;
revoke all on function security.register_replay_compare_v1(uuid) from public, anon, authenticated;

insert into pipeline.register_replay_runs(source_id, label, storage_path, zip_hash, keep_fields, created_at) values
  ('b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'CRICOS 11 Aug 2026', 'regulatory/AU/cricos/2026-08-11T20-37-14-519Z-providers-courses-locations.zip', null, false, now()),
  ('b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'CRICOS 26 Sep 2026', 'regulatory/AU/cricos/2026-09-26T13-31-40-537Z-providers-courses-locations.zip', 'e11def41515e8fc97d9b3c68aaff3dcfbce42a5a600b517b095b11c8fe254cd7', false, now() + interval '1 second'),
  ('b5680d74-49c5-49a5-b198-a625f3e3fdcf', 'CRICOS 30 Sep 2026 (newest)', 'regulatory/AU/cricos/2026-09-30T23-35-04-427Z-providers-courses-locations.zip', '8e298dcb5026a909e3dd581a148a953e260b6fb7302efba92521c27d5bffd4bb', true, now() + interval '2 seconds');
