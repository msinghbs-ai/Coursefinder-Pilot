-- CF-247 Wave 2 addenda (Platform Admin 17 Nov 2026 19:09, S1-RM-Design): Layer 1 source line items show which parser reads each source, and the
-- induction wizard takes a defined target record type so the AI mapper can propose a parser spec for it.
--   1. pipeline.layer1_source_parsers: one row per source whose parser is recorded: AI-built (a JSON parser spec, from the wizard and the AI mapper)
--      or hardcoded (a reader in code), its target record type, layout drift when a reader flags it, and a request to re-infer the spec.
--      A source with no row is shown as hardcoded when it has a reader, and as waiting for a parser when it does not.
--   2. public.admin_layer1_parser_status(): the badge and drift for every Layer 1 source (Pipeline Operator and above).
--      public.admin_layer1_parser_reinfer_request(source, reason): asks for the spec to be inferred again when drift is flagged. It records
--      the request and a control event; the AI mapper (S2-Build) acts on it. Nothing is re-read or re-parsed from here.
--   3. Service functions for the readers and the mapper: record a parser, flag or clear drift.
--   4. The wizard: seven target record types (step 1), and the parser spec the mapper proposes is saved with the draft (step 3) and becomes the
--      source's AI-built parser on activation. The four induction functions are replaced from their definitions of 20261117193000.
-- A recorded spec or a re-infer request switches nothing on: the source stays paused until a person resumes it.
-- G1: no job. G2: no operational value; input-safety bounds are marked fixed. G3: no consumer API object is touched.
-- Replaces: nothing (four induction functions extended in place).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $pre$ declare r record; begin
  if to_regclass('pipeline.layer1_source_inductions') is null or to_regclass('pipeline.layer1_source_operations') is null or to_regclass('pipeline.sources') is null
     or to_regclass('pipeline.admin_control_events') is null or to_regprocedure('security.current_role_rank()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
  -- the four functions replaced below are the ones this change was written against (or this change is already applied)
  for r in select * from (values ('security.layer1_induction_steps_v1(pipeline.layer1_source_inductions)', '8dcb609809443e60ceb192b796579c61'),
                                 ('public.admin_layer1_induction_read(uuid)', '55adb79297f228419c0d02aeb5c16f92'),
                                 ('public.admin_layer1_induction_save(uuid,jsonb,jsonb)', '0a8fac994a5a553968dc40df55d1a5a3'),
                                 ('public.admin_layer1_induction_activate(uuid,text)', '1f3ba519ed00322440d9347261cd7ec8')) v(f, m) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.m and obj_description(r.f::regprocedure, 'pg_proc') is distinct from 'cf247_wave2_parser' then
      raise exception '% is not the definition this change was written against', r.f;
    end if;
  end loop;
end $pre$;

-- the record types a Layer 1 source can be parsed into
create or replace function security.layer1_record_types_v1() returns jsonb
language sql immutable set search_path = '' as $fn$
  select jsonb_build_array(
    jsonb_build_object('key', 'course_register', 'label', 'Course register', 'help', 'Courses as an official register lists them.'),
    jsonb_build_object('key', 'provider_register', 'label', 'Provider register', 'help', 'Providers and their registrations.'),
    jsonb_build_object('key', 'tuition_fees', 'label', 'Tuition fees', 'help', 'Fees by course or provider.'),
    jsonb_build_object('key', 'study_rules', 'label', 'Study rules', 'help', 'Visa, work and study rules of a country.'),
    jsonb_build_object('key', 'destination_metrics', 'label', 'Destination metrics', 'help', 'City and region figures such as population and living costs.'),
    jsonb_build_object('key', 'career_outcomes', 'label', 'Career outcomes', 'help', 'Occupations, salaries and job outlook.'),
    jsonb_build_object('key', 'scholarships', 'label', 'Scholarships', 'help', 'Scholarships and their conditions.'))
$fn$;
revoke all on function security.layer1_record_types_v1() from public, anon, authenticated;
grant execute on function security.layer1_record_types_v1() to service_role;

create table if not exists pipeline.layer1_source_parsers (
  source_id uuid primary key,
  parser_kind text not null check (parser_kind in ('ai_built', 'hardcoded')),
  target_record_type text,
  parser_spec jsonb check (parser_spec is null or jsonb_typeof(parser_spec) = 'object'),
  spec_version integer not null default 1,
  spec_by text,
  reader text,
  induction_id uuid,
  drift_flagged_at timestamptz, drift_message text,
  reinfer_requested_at timestamptz, reinfer_requested_by uuid, reinfer_reason text,
  updated_by uuid, updated_at timestamptz not null default now(),
  check (parser_kind <> 'ai_built' or parser_spec is not null));
comment on table pipeline.layer1_source_parsers is 'Which parser reads a Layer 1 source: AI-built (a JSON parser spec proposed by the AI mapper and reviewed in the induction wizard) or hardcoded (a reader in code); its target record type; layout drift flagged by a reader; and a request to infer the spec again. A source with no row here is hardcoded when it has a reader. Recording a spec or a request runs nothing.';
alter table pipeline.layer1_source_parsers enable row level security;
revoke all on table pipeline.layer1_source_parsers from public, anon, authenticated;

-- the four induction functions, extended (target record type; parser spec)
create or replace function security.layer1_induction_steps_v1(p_row pipeline.layer1_source_inductions) returns jsonb
language sql stable set search_path = '' as $fn$
  select jsonb_build_object(
    'scheme', p_row.country_code is not null and coalesce(p_row.payload->>'scheme', '') <> '' and coalesce(p_row.payload->>'scheme_kind', '') <> ''
              and coalesce(p_row.payload->>'target_record_type', '') <> '',
    'source', coalesce(p_row.payload->>'source_label', '') <> '' and coalesce(p_row.payload->>'source_url', '') ~* '^https://' and coalesce(p_row.payload->>'authority_name', '') <> ''
              and coalesce(p_row.payload->>'connector_type', '') <> '' and coalesce(p_row.payload->>'terms_status', '') <> ''
              and (p_row.payload->>'terms_status' = 'not_required' or coalesce(p_row.payload->>'licence_name', '') <> ''),
    'mapping', jsonb_array_length(p_row.mappings) > 0,
    'cadence', coalesce(p_row.payload->>'cadence', '') in ('weekly', 'monthly', 'annual'),
    'dry_run', coalesce(p_row.dry_run->>'status', '') = 'passed',
    'dry_run_state', coalesce(p_row.dry_run->>'status', 'waiting_for_reader'),
    'parser_spec', coalesce(jsonb_typeof(p_row.payload->'parser_spec') = 'object', false),
    'activated', p_row.status = 'activated')
$fn$;

create or replace function public.admin_layer1_induction_read(p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  return jsonb_build_object(
    'rank', security.current_role_rank(),
    'options', jsonb_build_object(
      'countries', (select coalesce(jsonb_agg(jsonb_build_object('code', c.iso_alpha2, 'name', c.name) order by c.name), '[]'::jsonb) from ref.countries c where c.iso_alpha2 is not null),
      'schemes', (select coalesce(jsonb_agg(jsonb_build_object('scheme', s.scheme, 'kind', s.kind, 'country_code', s.country_code, 'label', s.label, 'authority', s.authority) order by s.country_code, s.kind, s.scheme), '[]'::jsonb) from ref.registration_schemes s),
      'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', k.category_key, 'label', k.label, 'description', k.description,
                       'fields', (select coalesce(jsonb_agg(jsonb_build_object('field', f.field, 'label', f.label, 'boost_category', f.boost_category) order by f.label), '[]'::jsonb) from ref.enrichment_category_fields f where f.category_key = k.category_key)) order by k.sort_order), '[]'::jsonb)
                     from ref.enrichment_categories k where k.active),
      'connector_types', jsonb_build_array('csv_file', 'xlsx_file', 'json_api', 'html_pages', 'pdf_document', 'manual_upload'),
      'record_types', security.layer1_record_types_v1(),
      'cadences', jsonb_build_array('weekly', 'monthly', 'annual'),
      'terms_statuses', jsonb_build_array('approved', 'pending', 'not_required'),
      'retention_defaults', jsonb_build_object(
        'staging_retention_days', (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'temporary_staging'),
        'raw_retention_days', (select p.default_retention_days from pipeline.retention_class_policies p where p.class_key = 'accepted_source_versions')),
      'dry_run_rows', security.pipeline_num_v1('layer1.induction_dry_run_rows', 100),
      'sample_rows', security.pipeline_num_v1('layer1.induction_sample_rows', 20),
      'postcode_min_share', security.pipeline_num_v1('destination.postcode_primary_min_share', 0.9)),
    'drafts', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'status', i.status, 'country_code', i.country_code, 'label', i.payload->>'source_label', 'updated_at', i.updated_at,
                 'steps', security.layer1_induction_steps_v1(i)) order by i.updated_at desc), '[]'::jsonb)
               from pipeline.layer1_source_inductions i
              where i.id in (select x.id from pipeline.layer1_source_inductions x where x.status = 'draft' or x.updated_at > now() - interval '30 days' order by x.updated_at desc limit 50)), -- fixed: list length of one screen
    'item', (select security.layer1_induction_item_v1(i) from pipeline.layer1_source_inductions i where i.id = p_id));
end $$;

create or replace function public.admin_layer1_induction_save(p_id uuid, p_payload jsonb, p_mappings jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p jsonb := coalesce(p_payload, '{}'::jsonb); v_row pipeline.layer1_source_inductions; v_cc text; v_clean jsonb := '{}'::jsonb; k text; v text; m jsonb; v_maps jsonb;
        v_max_sample int := security.pipeline_num_v1('layer1.induction_sample_rows', 20)::int; v_n numeric;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  if jsonb_typeof(p) <> 'object' then raise exception 'the draft must be an object' using errcode = '22023'; end if;
  if p_id is not null then
    select * into v_row from pipeline.layer1_source_inductions i where i.id = p_id for update;
    if v_row.id is null then raise exception 'draft not found' using errcode = '22023'; end if;
    if v_row.status <> 'draft' then raise exception 'this induction is % and can no longer be changed', v_row.status using errcode = '22023'; end if;
  end if;
  v_cc := upper(btrim(coalesce(p->>'country_code', v_row.country_code, '')));
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries c where c.iso_alpha2 = v_cc) then raise exception 'choose a country (two-letter ISO code)' using errcode = '22023'; end if;
  -- plain text values: trimmed, bounded
  foreach k in array array['scheme', 'scheme_kind', 'field_scheme', 'source_label', 'source_url', 'authority_name', 'dataset_class', 'connector_type', 'expected_format',
                           'licence_name', 'licence_url', 'attribution_text', 'terms_status', 'cadence', 'notes', 'sample_file_name', 'target_record_type'] loop
    v := btrim(coalesce(p->>k, v_row.payload->>k, ''));
    if length(v) > 600 then raise exception '% is too long (600 characters at most)', k using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object(k, v);
  end loop;
  if v_clean->>'scheme' <> '' and not exists (select 1 from ref.registration_schemes s where s.scheme = v_clean->>'scheme' and s.kind = v_clean->>'scheme_kind' and s.country_code = v_cc) then
    raise exception 'scheme % (%) is not registered for %; register it in ref.registration_schemes first', v_clean->>'scheme', v_clean->>'scheme_kind', v_cc using errcode = '22023';
  end if;
  if v_clean->>'source_url' <> '' and v_clean->>'source_url' !~* '^https://[^[:space:]/]+\.[^[:space:]]+$' then raise exception 'the source address must be an https address' using errcode = '22023'; end if;
  if v_clean->>'licence_url' <> '' and v_clean->>'licence_url' !~* '^https://[^[:space:]]+$' then raise exception 'the licence address must be an https address' using errcode = '22023'; end if;
  if v_clean->>'connector_type' not in ('', 'csv_file', 'xlsx_file', 'json_api', 'html_pages', 'pdf_document', 'manual_upload') then raise exception 'unknown connector type' using errcode = '22023'; end if;
  if v_clean->>'terms_status' not in ('', 'approved', 'pending', 'not_required') then raise exception 'terms of use are approved, pending or not required' using errcode = '22023'; end if;
  if v_clean->>'target_record_type' <> '' and not exists (select 1 from jsonb_array_elements(security.layer1_record_types_v1()) t where t->>'key' = v_clean->>'target_record_type') then
    raise exception 'unknown target record type' using errcode = '22023';
  end if;
  if v_clean->>'cadence' not in ('', 'weekly', 'monthly', 'annual') then raise exception 'the cadence is weekly, monthly or annual' using errcode = '22023'; end if;
  if v_clean->>'dataset_class' not in ('', 'register', 'statistics') then raise exception 'the type is register or statistics' using errcode = '22023'; end if;
  v_clean := v_clean || jsonb_build_object('edition_archiving', coalesce((p->>'edition_archiving')::boolean, (v_row.payload->>'edition_archiving')::boolean, true));
  -- per-source retention: recorded, not enforced. null days means kept permanently.
  foreach k in array array['staging_retention_days', 'raw_retention_days'] loop
    if p ? k then v_n := nullif(p->>k, '')::numeric; else v_n := nullif(v_row.payload->>k, '')::numeric; end if;
    if v_n is not null and (v_n <> trunc(v_n) or v_n < 1 or v_n > 36500) then raise exception '% is a whole number of days from 1 to 36,500, or empty for permanent', k using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object(k, v_n);
  end loop;
  -- an uploaded sample: column names and the first rows only
  m := coalesce(case when p ? 'sample' then p->'sample' end, v_row.payload->'sample');
  if m is not null and jsonb_typeof(m) = 'object' then
    if jsonb_typeof(m->'columns') <> 'array' or jsonb_array_length(m->'columns') > 300 then raise exception 'the sample needs its column names (300 at most)' using errcode = '22023'; end if; -- fixed: input-safety bound
    v_clean := v_clean || jsonb_build_object('sample', jsonb_build_object('columns', m->'columns', 'total_rows', nullif(m->>'total_rows', '')::bigint,
      'rows', (select coalesce(jsonb_agg(r.value order by r.ord), '[]'::jsonb) from jsonb_array_elements(case when jsonb_typeof(m->'rows') = 'array' then m->'rows' else '[]'::jsonb end) with ordinality r(value, ord) where r.ord <= v_max_sample)));
    if pg_column_size(v_clean->'sample') > 400000 then raise exception 'the sample is too large; keep fewer or narrower rows' using errcode = '22023'; end if; -- fixed: input-safety bound
  end if;
  -- the parser spec the AI mapper proposed for this record type (kept as given; a person reviews it before activation)
  m := coalesce(case when p ? 'parser_spec' then p->'parser_spec' end, v_row.payload->'parser_spec');
  if m is not null and jsonb_typeof(m) = 'object' then
    if pg_column_size(m) > 200000 then raise exception 'the parser spec is too large' using errcode = '22023'; end if; -- fixed: input-safety bound
    if coalesce(m->>'record_type', v_clean->>'target_record_type') is distinct from v_clean->>'target_record_type' then raise exception 'the parser spec is for another record type; run AI Auto-Map again' using errcode = '22023'; end if;
    v_clean := v_clean || jsonb_build_object('parser_spec', m, 'parser_spec_by', coalesce(nullif(p->>'parser_spec_by', ''), v_row.payload->>'parser_spec_by', 'ai'));
  end if;
  -- mappings: source field to a coverage field and its category
  v_maps := coalesce(p_mappings, v_row.mappings, '[]'::jsonb);
  if jsonb_typeof(v_maps) <> 'array' or jsonb_array_length(v_maps) > 500 then raise exception 'the mappings must be a list (500 at most)' using errcode = '22023'; end if; -- fixed: input-safety bound
  for m in select value from jsonb_array_elements(v_maps) loop
    if coalesce(btrim(m->>'source_field'), '') = '' then raise exception 'every mapping names its source field' using errcode = '22023'; end if;
    if coalesce(m->>'category_key', '') <> '' and not exists (select 1 from ref.enrichment_categories c where c.category_key = m->>'category_key') then raise exception 'unknown category %', m->>'category_key' using errcode = '22023'; end if;
    if coalesce(m->>'target_field', '') <> '' and coalesce(m->>'target_field', '') !~ '^[a-z0-9_.]{2,80}$' then raise exception 'target field % is not a field name', m->>'target_field' using errcode = '22023'; end if;
    if coalesce(m->>'by', 'manual') not in ('manual', 'ai', 'ai_adjusted') then raise exception 'a mapping is manual, ai or ai_adjusted' using errcode = '22023'; end if;
  end loop;
  if p_id is null then
    insert into pipeline.layer1_source_inductions(country_code, payload, mappings, created_by, updated_by) values (v_cc, v_clean, v_maps, auth.uid(), auth.uid()) returning * into v_row;
  else
    update pipeline.layer1_source_inductions i set country_code = v_cc, payload = v_clean, mappings = v_maps, updated_by = auth.uid(), updated_at = now() where i.id = p_id returning * into v_row;
  end if;
  return jsonb_build_object('ok', true, 'item', security.layer1_induction_item_v1(v_row));
end $$;

create or replace function public.admin_layer1_induction_activate(p_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_row pipeline.layer1_source_inductions; s jsonb; v_added jsonb; v_source uuid; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin (rank 6) activates a new source' using errcode = '42501'; end if; -- fixed: activation is the Platform Admin's
  if v_reason is null or length(v_reason) < 4 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into v_row from pipeline.layer1_source_inductions i where i.id = p_id for update;
  if v_row.id is null then raise exception 'draft not found' using errcode = '22023'; end if;
  if v_row.status <> 'draft' then raise exception 'this induction is already %', v_row.status using errcode = '22023'; end if;
  s := security.layer1_induction_steps_v1(v_row);
  if not (s->>'scheme')::boolean then raise exception 'step 1 is not finished: choose the country, scheme and target record type' using errcode = '22023'; end if;
  if not (s->>'source')::boolean then raise exception 'step 2 is not finished: source address, authority, connector and licence terms' using errcode = '22023'; end if;
  if not (s->>'mapping')::boolean then raise exception 'step 3 is not finished: map at least one field' using errcode = '22023'; end if;
  if not (s->>'cadence')::boolean then raise exception 'step 4 is not finished: choose the cadence' using errcode = '22023'; end if;
  if coalesce(v_row.dry_run->>'status', '') = 'failed' then raise exception 'the dry run failed; fix the source or its mapping and run it again' using errcode = '22023'; end if;
  v_added := public.admin_layer1_add_source(jsonb_build_object('country_code', v_row.country_code, 'label', v_row.payload->>'source_label', 'url', v_row.payload->>'source_url',
    'authority_name', v_row.payload->>'authority_name', 'dataset_class', coalesce(nullif(v_row.payload->>'dataset_class', ''), 'register'),
    'ingestion_cadence_days', case v_row.payload->>'cadence' when 'weekly' then 7 when 'monthly' then 30 else 365 end, -- fixed: days in the named cadence
    'expected_format', v_row.payload->>'connector_type', 'notes', nullif(v_row.payload->>'notes', ''), 'reason', v_reason));
  v_source := (v_added->>'source_id')::uuid;
  update pipeline.layer1_source_inductions i set status = 'activated', source_id = v_source, activated_by = auth.uid(), activated_at = now(), activation_reason = v_reason,
         updated_by = auth.uid(), updated_at = now() where i.id = p_id returning * into v_row;
  -- the parser this source will use: AI-built when the mapper's spec was saved with the draft; otherwise it waits for a parser
  if jsonb_typeof(v_row.payload->'parser_spec') = 'object' then
    insert into pipeline.layer1_source_parsers(source_id, parser_kind, target_record_type, parser_spec, spec_by, induction_id, updated_by)
    values (v_source, 'ai_built', v_row.payload->>'target_record_type', v_row.payload->'parser_spec', coalesce(v_row.payload->>'parser_spec_by', 'ai'), v_row.id, auth.uid())
    on conflict (source_id) do nothing;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'induction_activate', v_source::text, jsonb_build_object('reason', v_reason, 'induction_id', v_row.id, 'label', v_row.payload->>'source_label', 'country', v_row.country_code,
          'scheme', v_row.payload->>'scheme', 'target_record_type', v_row.payload->>'target_record_type', 'parser', case when jsonb_typeof(v_row.payload->'parser_spec') = 'object' then 'ai_built' else 'none' end, 'terms_status', v_row.payload->>'terms_status', 'dry_run', s->>'dry_run_state', 'source_paused', true), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'source_id', v_source, 'source_paused', true, 'dry_run', s->>'dry_run_state', 'event_id', v_ev, 'item', security.layer1_induction_item_v1(v_row));
end $$;

comment on function security.layer1_induction_steps_v1(pipeline.layer1_source_inductions) is 'cf247_wave2_parser';
comment on function public.admin_layer1_induction_read(uuid) is 'cf247_wave2_parser';
comment on function public.admin_layer1_induction_save(uuid, jsonb, jsonb) is 'cf247_wave2_parser';
comment on function public.admin_layer1_induction_activate(uuid, text) is 'cf247_wave2_parser';

-- the parser badge and drift of every Layer 1 source
create or replace function public.admin_layer1_parser_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  return jsonb_build_object('record_types', security.layer1_record_types_v1(),
    'sources', (select coalesce(jsonb_object_agg(o.source_id::text, jsonb_build_object(
        'parser', coalesce(p.parser_kind, case when coalesce(s.metadata->>'needs_reader', 'false') = 'true' then 'none' else 'hardcoded' end),
        'target_record_type', p.target_record_type, 'spec_version', case when p.parser_kind = 'ai_built' then p.spec_version end, 'reader', p.reader,
        'drift_flagged_at', p.drift_flagged_at, 'drift_message', p.drift_message,
        'reinfer_requested_at', p.reinfer_requested_at, 'reinfer_reason', p.reinfer_reason)), '{}'::jsonb)
      from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id left join pipeline.layer1_source_parsers p on p.source_id = o.source_id));
end $$;

-- ask for the parser spec to be inferred again, when a reader has flagged that the source's layout changed
create or replace function public.admin_layer1_parser_reinfer_request(p_source_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_row pipeline.layer1_source_parsers; v_ev bigint;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator (rank 4) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
  if v_reason is null or length(v_reason) < 4 then raise exception 'a reason is required' using errcode = '22023'; end if;
  select * into v_row from pipeline.layer1_source_parsers p where p.source_id = p_source_id for update;
  if v_row.source_id is null or v_row.drift_flagged_at is null then raise exception 'no layout drift is flagged for this source' using errcode = '22023'; end if;
  if v_row.reinfer_requested_at is not null then raise exception 'a re-infer is already requested for this source' using errcode = '22023'; end if;
  update pipeline.layer1_source_parsers p set reinfer_requested_at = now(), reinfer_requested_by = auth.uid(), reinfer_reason = v_reason, updated_by = auth.uid(), updated_at = now()
   where p.source_id = p_source_id returning * into v_row;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'parser_reinfer_request', p_source_id::text, jsonb_build_object('reason', v_reason, 'parser', v_row.parser_kind, 'spec_version', v_row.spec_version, 'drift_message', v_row.drift_message), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'source_id', p_source_id, 'requested_at', v_row.reinfer_requested_at, 'event_id', v_ev);
end $$;

-- for the readers and the AI mapper (service role): record the parser of a source; a new spec clears drift and the request
create or replace function public.svc_layer1_parser_record(p_source_id uuid, p_record jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb := coalesce(p_record, '{}'::jsonb); v_row pipeline.layer1_source_parsers;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = p_source_id) then raise exception 'not a Layer 1 source' using errcode = '22023'; end if;
  if r->>'parser_kind' not in ('ai_built', 'hardcoded') then raise exception 'a parser is ai_built or hardcoded' using errcode = '22023'; end if;
  if r->>'parser_kind' = 'ai_built' and jsonb_typeof(r->'parser_spec') is distinct from 'object' then raise exception 'an AI-built parser needs its spec' using errcode = '22023'; end if;
  if coalesce(r->>'target_record_type', '') <> '' and not exists (select 1 from jsonb_array_elements(security.layer1_record_types_v1()) t where t->>'key' = r->>'target_record_type') then
    raise exception 'unknown target record type' using errcode = '22023';
  end if;
  if pg_column_size(r) > 200000 then raise exception 'the parser spec is too large' using errcode = '22023'; end if; -- fixed: input-safety bound
  insert into pipeline.layer1_source_parsers(source_id, parser_kind, target_record_type, parser_spec, spec_by, reader)
  values (p_source_id, r->>'parser_kind', nullif(r->>'target_record_type', ''), case when r->>'parser_kind' = 'ai_built' then r->'parser_spec' end, left(coalesce(r->>'spec_by', 'ai'), 60), left(nullif(r->>'reader', ''), 120))
  on conflict (source_id) do update set parser_kind = excluded.parser_kind, target_record_type = coalesce(excluded.target_record_type, pipeline.layer1_source_parsers.target_record_type),
    parser_spec = excluded.parser_spec, spec_by = excluded.spec_by, reader = coalesce(excluded.reader, pipeline.layer1_source_parsers.reader),
    spec_version = pipeline.layer1_source_parsers.spec_version + 1, drift_flagged_at = null, drift_message = null,
    reinfer_requested_at = null, reinfer_requested_by = null, reinfer_reason = null, updated_at = now()
  returning * into v_row;
  return jsonb_build_object('ok', true, 'source_id', v_row.source_id, 'parser', v_row.parser_kind, 'spec_version', v_row.spec_version);
end $$;

create or replace function public.svc_layer1_parser_drift_record(p_source_id uuid, p_flagged boolean, p_message text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_row pipeline.layer1_source_parsers;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  if not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = p_source_id) then raise exception 'not a Layer 1 source' using errcode = '22023'; end if;
  -- a source read by code gets its row the first time its reader reports
  insert into pipeline.layer1_source_parsers(source_id, parser_kind) values (p_source_id, 'hardcoded') on conflict (source_id) do nothing;
  update pipeline.layer1_source_parsers p set drift_flagged_at = case when coalesce(p_flagged, false) then coalesce(p.drift_flagged_at, now()) end,
         drift_message = case when coalesce(p_flagged, false) then left(coalesce(p_message, ''), 600) end, updated_at = now()
   where p.source_id = p_source_id returning * into v_row;
  return jsonb_build_object('ok', true, 'source_id', p_source_id, 'drift_flagged', v_row.drift_flagged_at is not null);
end $$;

revoke all on function public.admin_layer1_parser_status() from public, anon;
revoke all on function public.admin_layer1_parser_reinfer_request(uuid, text) from public, anon;
revoke all on function public.svc_layer1_parser_record(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.svc_layer1_parser_drift_record(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.admin_layer1_parser_status() to authenticated, service_role;
grant execute on function public.admin_layer1_parser_reinfer_request(uuid, text) to authenticated, service_role;
grant execute on function public.svc_layer1_parser_record(uuid, jsonb) to service_role;
grant execute on function public.svc_layer1_parser_drift_record(uuid, boolean, text) to service_role;

-- Post-check
do $$ begin
  if jsonb_array_length(security.layer1_record_types_v1()) <> 7 or to_regclass('pipeline.layer1_source_parsers') is null
     or has_function_privilege('authenticated', 'public.svc_layer1_parser_record(uuid, jsonb)', 'execute') then
    raise exception 'post-check: layer 1 parsers';
  end if;
end $$;
