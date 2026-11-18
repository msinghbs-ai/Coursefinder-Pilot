-- CF-247 Wave 2 decisions (Platform Admin 17 Nov 2026 19:58 and 20:45, S1-RM-Design): one category list, one place for per-source retention, and
-- Curators in Layer 1.
--   1. Categories. ref.enrichment_categories and ref.enrichment_category_fields are the single list of the eight enrichment categories.
--      public.svc_enrichment_categories() publishes the keys, labels and fields to every loader and worker (service role).
--      ref.enrichment_category_fields.boost_category stays only as the crosswalk from the Boost matrix keys of migration 20261117183000 until the
--      Boost matrix reads this list; it is not a second list.
--   2. Retention. The wizard no longer keeps its own retention values. A draft carries one optional staging keep period; on activation it is set
--      through public.admin_source_retention_set (pipeline.source_retention_policies, S1-Build, migration 20261117200000), which housekeeping-daily
--      reads. The completeness report reads the same table and the retention.* settings.
--   3. Roles. Curator (rank 3) and above open Layer 1 and create and edit wizard drafts. Re-infer Parser Spec stays Pipeline Operator (rank 4)
--      and above; activation stays the Platform Admin's (rank 6). Every other Layer 1 control keeps its own rank.
-- Functions are changed only from the definitions this change was written against (md5 checked); nothing is dropped.
-- G1: no job. G2: periods come from the retention.* settings; fixed bounds are marked. G3: no consumer API object is touched.
-- Replaces: the wizard's own per-source retention values (payload keys staging_retention_days and raw_retention_days; no draft held them).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $pre$ declare r record; begin
  if to_regclass('pipeline.layer1_source_inductions') is null or to_regclass('pipeline.layer1_source_parsers') is null or to_regclass('ref.enrichment_category_fields') is null
     or to_regclass('pipeline.source_retention_policies') is null or to_regprocedure('public.admin_source_retention_set(uuid,integer,text)') is null
     or to_regprocedure('security.pipeline_num_v1(text,numeric)') is null then
    raise exception 'an object this change builds on is missing';
  end if;
  for r in select * from (values ('public.admin_layer1_induction_read(uuid)', '451ca2a1809f243d5c4057143c3d3800'),
                                 ('public.admin_layer1_induction_save(uuid,jsonb,jsonb)', 'e1812f469090dd104ac480d4abcd9639'),
                                 ('public.admin_layer1_induction_activate(uuid,text)', '0b699036ccd9f32cf4d19f1c8fc23c4b'),
                                 ('public.admin_completeness_report()', '069ecb2f176828ad14b6d034fc0d0e1a')) v(f, m) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.m and obj_description(r.f::regprocedure, 'pg_proc') is distinct from 'cf247_wave2_unify' then
      raise exception '% is not the definition this change was written against', r.f;
    end if;
  end loop;
end $pre$;

-- one exact text change in a function that is otherwise left as it is: applied when the definition is the one expected, skipped when already applied
create or replace function pg_temp.swap_once(p_fn text, p_before text, p_after text, p_old text, p_new text) returns text
language plpgsql as $fn$
declare v_def text; v_md5 text;
begin
  if to_regprocedure(p_fn) is null then return 'absent'; end if;
  v_def := pg_get_functiondef(p_fn::regprocedure); v_md5 := md5(v_def);
  if v_md5 = p_after then return 'already'; end if;
  if v_md5 <> p_before then raise exception '% is not the definition this change was written against', p_fn; end if;
  if (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old) <> 1 then raise exception '% does not hold the expected text exactly once', p_fn; end if;
  execute replace(v_def, p_old, p_new);
  if md5(pg_get_functiondef(p_fn::regprocedure)) <> p_after then raise exception '% did not become the expected definition', p_fn; end if;
  return 'changed';
end $fn$;

-- 3. Roles: Curator and above open Layer 1 (the list read, the parser badges, cancelling a draft)
select pg_temp.swap_once('security.admin_layer1_operations_read(jsonb)', '0e93afeba4d14c2ad2ce2d492ffd14d4', '3af9dff07f35f774e935fc590552ce13',
  'if coalesce(v_rank,0)<4 then raise exception ''pipeline_operator role required''', 'if coalesce(v_rank,0)<3 then raise exception ''curator role required''');
select pg_temp.swap_once('public.admin_layer1_induction_cancel(uuid,text)', 'a1495dedd6b2a83b707c335f65adb64f', 'e398757990252f00bc6209c502cbbdf4',
  'security.current_role_rank(), 0) < 4 then raise exception ''Pipeline Operator (rank 4) or above is needed for Layer 1''', 'security.current_role_rank(), 0) < 3 then raise exception ''Curator (rank 3) or above is needed for Layer 1''');
select pg_temp.swap_once('public.admin_layer1_parser_status()', 'bd268472792321d123f23df60a1b5761', 'f01c746a4d9c239b2530029e2b9ce2bb',
  'security.current_role_rank(), 0) < 4 then raise exception ''Pipeline Operator (rank 4) or above is needed for Layer 1''', 'security.current_role_rank(), 0) < 3 then raise exception ''Curator (rank 3) or above is needed for Layer 1''');

-- 1. Categories: the one list, published
comment on column ref.enrichment_category_fields.boost_category is 'Crosswalk only: the Boost matrix key (setting country_category_boost, migration 20261117183000) this field fell under. Kept until the Boost matrix reads ref.enrichment_categories; not a category list.';

create or replace function security.enrichment_categories_v1() returns jsonb
language sql stable security definer set search_path = '' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('key', k.category_key, 'label', k.label, 'description', k.description, 'sort_order', k.sort_order,
           'fields', (select coalesce(jsonb_agg(jsonb_build_object('field', f.field, 'label', f.label) order by f.field), '[]'::jsonb) from ref.enrichment_category_fields f where f.category_key = k.category_key))
         order by k.sort_order), '[]'::jsonb)
    from ref.enrichment_categories k where k.active
$fn$;
revoke all on function security.enrichment_categories_v1() from public, anon, authenticated;

create or replace function public.svc_enrichment_categories() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  return jsonb_build_object('version', 1, 'categories', security.enrichment_categories_v1());
end $$;
revoke all on function public.svc_enrichment_categories() from public, anon, authenticated;
grant execute on function public.svc_enrichment_categories() to service_role;

-- 2 and 3. The wizard read, save and activation, and the completeness report
create or replace function public.admin_layer1_induction_read(p_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
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
        'staging_keep_days', security.pipeline_num_v1('retention.staging_keep_days', 90),
        'raw_hash_keep_years', security.pipeline_num_v1('retention.raw_hash_keep_years', 7),
        'staging_prune_on', security.pipeline_num_v1('retention.staging_prune_on', 0) >= 1),
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
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for Layer 1' using errcode = '42501'; end if; -- fixed: who opens Layer 1
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
  -- per-source staging keep period: written to pipeline.source_retention_policies on activation, which housekeeping-daily reads. Empty = the platform period.
  if p ? 'staging_keep_days' then v_n := nullif(p->>'staging_keep_days', '')::numeric; else v_n := nullif(v_row.payload->>'staging_keep_days', '')::numeric; end if;
  if v_n is not null and (v_n <> trunc(v_n) or v_n < 30 or v_n > 3650) then raise exception 'staging is kept for a whole number of days from 30 to 3,650, or empty for the platform period' using errcode = '22023'; end if; -- fixed: the range pipeline.source_retention_policies accepts
  v_clean := v_clean || jsonb_build_object('staging_keep_days', v_n);
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
  -- its own staging keep period, when one was entered: set through S1-Build's function, so housekeeping-daily follows it (logged there too)
  if nullif(v_row.payload->>'staging_keep_days', '') is not null then
    perform public.admin_source_retention_set(v_source, (v_row.payload->>'staging_keep_days')::int, 'Induction wizard: ' || v_reason);
  end if;
  -- the parser this source will use: AI-built when the mapper's spec was saved with the draft; otherwise it waits for a parser
  if jsonb_typeof(v_row.payload->'parser_spec') = 'object' then
    insert into pipeline.layer1_source_parsers(source_id, parser_kind, target_record_type, parser_spec, spec_by, induction_id, updated_by)
    values (v_source, 'ai_built', v_row.payload->>'target_record_type', v_row.payload->'parser_spec', coalesce(v_row.payload->>'parser_spec_by', 'ai'), v_row.id, auth.uid())
    on conflict (source_id) do nothing;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'induction_activate', v_source::text, jsonb_build_object('reason', v_reason, 'induction_id', v_row.id, 'label', v_row.payload->>'source_label', 'country', v_row.country_code,
          'scheme', v_row.payload->>'scheme', 'target_record_type', v_row.payload->>'target_record_type', 'parser', case when jsonb_typeof(v_row.payload->'parser_spec') = 'object' then 'ai_built' else 'none' end, 'terms_status', v_row.payload->>'terms_status', 'staging_keep_days', nullif(v_row.payload->>'staging_keep_days', '')::int, 'dry_run', s->>'dry_run_state', 'source_paused', true), auth.uid()) returning id into v_ev;
  return jsonb_build_object('ok', true, 'source_id', v_source, 'source_paused', true, 'dry_run', s->>'dry_run_state', 'event_id', v_ev, 'item', security.layer1_induction_item_v1(v_row));
end $$;

create or replace function public.admin_completeness_report() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_day date; v_warn int := security.pipeline_num_v1('health.layer4_age_warn_days', 7)::int; v_old int := greatest(security.pipeline_num_v1('health.layer4_age_old_days', 30)::int, v_warn + 1);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator (rank 3) or above is needed for this report' using errcode = '42501'; end if; -- fixed: Platform health opens at Curator
  select max(f.snapshot_date) into v_day from pipeline.field_coverage_daily f;
  return jsonb_build_object(
    'rank', security.current_role_rank(), 'snapshot_date', v_day,
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', k.category_key, 'label', k.label, 'description', k.description) order by k.sort_order), '[]'::jsonb) from ref.enrichment_categories k where k.active),
    'countries', (select coalesce(jsonb_agg(distinct f.country_code order by f.country_code), '[]'::jsonb) from pipeline.field_coverage_daily f where f.snapshot_date = v_day),
    'cells', (select coalesce(jsonb_agg(jsonb_build_object('country_code', x.country_code, 'category_key', x.category_key, 'total', x.total, 'filled', x.filled,
                'pct', case when x.total > 0 then round(100.0 * x.filled / x.total, 1) end, 'fields', x.fields) order by x.country_code, x.category_key), '[]'::jsonb)
              from (select f.country_code, coalesce(m.category_key, 'unmapped') as category_key, sum(f.total) as total, sum(f.filled) as filled,
                           jsonb_agg(jsonb_build_object('field', f.field, 'label', coalesce(m.label, f.field), 'total', f.total, 'filled', f.filled,
                             'pct', case when f.total > 0 then round(100.0 * f.filled / f.total, 1) end) order by f.field) as fields
                      from pipeline.field_coverage_daily f left join ref.enrichment_category_fields m on m.field = f.field
                     where f.snapshot_date = v_day group by 1, 2) x),
    'editions', (select coalesce(jsonb_agg(jsonb_build_object('source_id', s.id, 'label', s.label, 'country_code', c.iso_alpha2, 'paused', o.paused, 'source_status', s.status,
                   'editions_kept', e.n, 'current_edition', e.current_key, 'edition_last_verified_at', e.last_verified,
                   'last_verified_at', o.last_verified_at, 'verification_status', o.verification_status, 'previous_count', o.previous_accepted_count, 'last_count', o.last_expected_count,
                   'variance_percent', o.variance_percent, 'variance_decision', o.variance_decision,
                   'retention', jsonb_build_object('per_source', rp.source_id is not null, 'staging_keep_days', coalesce(rp.staging_keep_days, pol.staging),
                     'raw_hash_keep_years', pol.hash_years, 'edition_archiving', coalesce((i.payload->>'edition_archiving')::boolean, true)))
                   order by c.iso_alpha2, s.label), '[]'::jsonb)
                 from pipeline.layer1_source_operations o join pipeline.sources s on s.id = o.source_id left join ref.countries c on c.id = s.country_id
                 left join lateral (select count(*) as n, max(d.edition_key) filter (where d.status = 'current') as current_key, max(d.last_verified_at) as last_verified
                                      from pipeline.layer1_dataset_editions d where d.source_id = s.id) e on true
                 left join lateral (select x.id, x.payload from pipeline.layer1_source_inductions x where x.source_id = s.id order by x.updated_at desc limit 1) i on true
                 left join pipeline.source_retention_policies rp on rp.source_id = s.id
                 cross join (select security.pipeline_num_v1('retention.staging_keep_days', 90)::int as staging, security.pipeline_num_v1('retention.raw_hash_keep_years', 7)::int as hash_years) pol
                where s.status <> 'retired'),
    'retention_settings', jsonb_build_object('staging_keep_days', security.pipeline_num_v1('retention.staging_keep_days', 90)::int, 'raw_hash_keep_years', security.pipeline_num_v1('retention.raw_hash_keep_years', 7)::int,
                                             'staging_prune_on', security.pipeline_num_v1('retention.staging_prune_on', 0) >= 1),
    'retention_policy', (select coalesce(jsonb_agg(jsonb_build_object('class_key', p.class_key, 'days', p.default_retention_days, 'immutable', p.immutable, 'purge_allowed', p.purge_allowed) order by p.class_key), '[]'::jsonb)
                         from pipeline.retention_class_policies p),
    'layer4', jsonb_build_object('warn_days', v_warn, 'old_days', v_old,
      'pending', (select count(*) from pipeline.layer4_review_items r where r.status = 'pending'),
      'oldest_at', (select min(r.created_at) from pipeline.layer4_review_items r where r.status = 'pending'),
      'by_type', (select coalesce(jsonb_agg(jsonb_build_object('entity_type', x.entity_type, 'pending', x.n, 'fresh', x.fresh, 'waiting', x.waiting, 'old', x.old, 'oldest_at', x.oldest) order by x.n desc), '[]'::jsonb)
                  from (select r.entity_type, count(*) as n, count(*) filter (where r.created_at > now() - make_interval(days => v_warn)) as fresh,
                               count(*) filter (where r.created_at <= now() - make_interval(days => v_warn) and r.created_at > now() - make_interval(days => v_old)) as waiting,
                               count(*) filter (where r.created_at <= now() - make_interval(days => v_old)) as old, min(r.created_at) as oldest
                          from pipeline.layer4_review_items r where r.status = 'pending' group by 1) x)));
end $$;

comment on function public.admin_layer1_induction_read(uuid) is 'cf247_wave2_unify';
comment on function public.admin_layer1_induction_save(uuid, jsonb, jsonb) is 'cf247_wave2_unify';
comment on function public.admin_layer1_induction_activate(uuid, text) is 'cf247_wave2_unify';
comment on function public.admin_completeness_report() is 'cf247_wave2_unify';

-- Post-check
do $$ begin
  if jsonb_array_length(security.enrichment_categories_v1()) <> 8
     or (select sum(jsonb_array_length(c->'fields')) from jsonb_array_elements(security.enrichment_categories_v1()) c) < 32
     or has_function_privilege('authenticated', 'public.svc_enrichment_categories()', 'execute')
     or position('< 3 then' in pg_get_functiondef('public.admin_layer1_induction_save(uuid,jsonb,jsonb)'::regprocedure)) = 0
     or position('< 6 then' in pg_get_functiondef('public.admin_layer1_induction_activate(uuid,text)'::regprocedure)) = 0
     or position('< 4 then' in pg_get_functiondef('public.admin_layer1_parser_reinfer_request(uuid,text)'::regprocedure)) = 0 then
    raise exception 'post-check: wave 2 decisions';
  end if;
end $$;
