-- CF-247 Wave 2, PR A (S2-Build; Platform Admin 17 Nov 2026 17:55, 19:08 and 19:58; Mapper Contract v1.1 of S1-RM-Design, 20:10):
-- the declarative parser spec contract behind the AI induction mapper.
--   1. security.layer1_parser_targets_v1(): for each of the seven target record types (security.layer1_record_types_v1), the table its rows
--      reach, through which proven apply path, and the only target fields a spec may name (type, required, key). A spec cannot name anything
--      else: no table, column, SQL or code of its own.
--   2. security.layer1_parser_spec_validate_v1(spec, record_type, columns): the strict check every AI-built spec passes before it is shown,
--      saved, or run. Unknown keys are refused at every level; formats, types, transforms and date patterns come from fixed lists; the unique
--      key must be mapped fields; attribution is required; expected headers must be in the sample. Errors are plain sentences.
--   3. Settings for the mapper (G2): the pinned model (one named model; the contract forbids an "auto" model), calls a day, answer size.
--   4. Service functions for the edge function layer1-ai-induction-mapper (deployed in the same change): validate a spec, and log a call and
--      count today's calls. The mapper writes nothing else; a person reviews every suggestion in the wizard.
-- G1: no job. G2: limits are settings; input-safety bounds are marked fixed. G3: no consumer API object is touched.
-- Replaces: nothing (the wizard maps by hand until the mapper answers status; Mapper Contract v1.1).
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety

do $pre$ begin
  if to_regprocedure('security.layer1_record_types_v1()') is null or to_regclass('pipeline.layer1_source_parsers') is null
     or to_regclass('ref.enrichment_categories') is null or to_regprocedure('public.svc_layer1_register_settings_v1()') is null then
    raise exception 'an object this change builds on is missing';
  end if;
end $pre$;

-- 1. settings
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'layer1.induction_mapper_model', 'Layer 1 induction: pinned AI mapper model',
  'The one model the AI induction mapper uses to suggest field mappings and a parser spec. A person reviews every suggestion; change it only to another qualified model.',
  'text', to_jsonb('openai/gpt-4.1-mini'::text), null, null, 'model id', 1210, 'Wave 2 mapper (S2-Build, Platform Admin 17 Nov 2026 17:55); the model already pinned for entry matrices', 'Layer 1 register',
  'layer1-ai-induction-mapper'),
 ('pipeline', 'layer1.induction_mapper_calls_per_day', 'Layer 1 induction: AI mapper calls a day',
  'The most AI Auto-Map and re-infer calls the mapper makes in one Sydney day; further calls answer that the daily limit is reached.',
  'number', to_jsonb(200), 1, 2000, 'calls', 1211, 'Wave 2 mapper (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-ai-induction-mapper'),
 ('pipeline', 'layer1.induction_mapper_max_tokens', 'Layer 1 induction: AI mapper answer size',
  'The largest answer the mapper asks the model for, in tokens.',
  'number', to_jsonb(4000), 500, 16000, 'tokens', 1212, 'Wave 2 mapper (S2-Build, 17 Nov 2026)', 'Layer 1 register', 'layer1-ai-induction-mapper')
on conflict (toolset_key, key) do nothing;

-- 2. the allowed targets of each record type
create or replace function security.layer1_parser_targets_v1()
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'course_register', jsonb_build_object('target_table', 'catalogue.courses', 'apply', 'public.svc_layer1_apply_register_records', 'key', jsonb_build_array('provider_code', 'course_code'),
      'fields', jsonb_build_object(
        'provider_code', jsonb_build_object('type', 'code', 'required', true), 'provider_name', jsonb_build_object('type', 'text', 'required', true),
        'course_code', jsonb_build_object('type', 'code', 'required', true), 'course_name', jsonb_build_object('type', 'text', 'required', true),
        'course_level', jsonb_build_object('type', 'text'), 'duration_weeks', jsonb_build_object('type', 'numeric'),
        'field_code', jsonb_build_object('type', 'code'), 'field_name', jsonb_build_object('type', 'text'), 'website', jsonb_build_object('type', 'url'),
        'city', jsonb_build_object('type', 'text'), 'state', jsonb_build_object('type', 'text'), 'postcode', jsonb_build_object('type', 'code'),
        'address_line1', jsonb_build_object('type', 'text'), 'address_line2', jsonb_build_object('type', 'text'))),
    'provider_register', jsonb_build_object('target_table', 'catalogue.providers', 'apply', 'public.svc_layer1_apply_register_records', 'key', jsonb_build_array('provider_code'),
      'fields', jsonb_build_object(
        'provider_code', jsonb_build_object('type', 'code', 'required', true), 'provider_name', jsonb_build_object('type', 'text', 'required', true),
        'provider_classification', jsonb_build_object('type', 'text'), 'website', jsonb_build_object('type', 'url'), 'city', jsonb_build_object('type', 'text'),
        'state', jsonb_build_object('type', 'text'), 'postcode', jsonb_build_object('type', 'code'), 'address_line1', jsonb_build_object('type', 'text'),
        'address_line2', jsonb_build_object('type', 'text'))),
    'tuition_fees', jsonb_build_object('target_table', 'catalogue.course_fees', 'apply', 'staged for review', 'key', jsonb_build_array('provider_code', 'course_code', 'fee_year', 'audience'),
      'fields', jsonb_build_object(
        'provider_code', jsonb_build_object('type', 'code', 'required', true), 'course_code', jsonb_build_object('type', 'code', 'required', true),
        'amount', jsonb_build_object('type', 'currency_amount', 'required', true), 'currency_code', jsonb_build_object('type', 'code'),
        'fee_year', jsonb_build_object('type', 'integer'), 'audience', jsonb_build_object('type', 'text'), 'basis', jsonb_build_object('type', 'text'),
        'campus_name', jsonb_build_object('type', 'text'))),
    'study_rules', jsonb_build_object('target_table', 'destination.study_rules', 'apply', 'staged for review', 'key', jsonb_build_array('rule_category', 'title', 'state_code'),
      'fields', jsonb_build_object(
        'rule_category', jsonb_build_object('type', 'text', 'required', true), 'title', jsonb_build_object('type', 'text', 'required', true),
        'summary', jsonb_build_object('type', 'text'), 'visa_subclass', jsonb_build_object('type', 'code'), 'visa_name', jsonb_build_object('type', 'text'),
        'state_code', jsonb_build_object('type', 'code'), 'applicant_scope', jsonb_build_object('type', 'text'), 'numeric_threshold', jsonb_build_object('type', 'numeric'),
        'currency_code', jsonb_build_object('type', 'code'), 'effective_from', jsonb_build_object('type', 'date'), 'effective_to', jsonb_build_object('type', 'date'),
        'quote_on_page', jsonb_build_object('type', 'text', 'required', true), 'source_url', jsonb_build_object('type', 'url', 'required', true))),
    'destination_metrics', jsonb_build_object('target_table', 'destination.locality_metrics', 'apply', 'staged for review', 'key', jsonb_build_array('geography_code', 'metric_key', 'reference_period'),
      'fields', jsonb_build_object(
        'geography_type', jsonb_build_object('type', 'code'), 'geography_code', jsonb_build_object('type', 'code', 'required', true),
        'locality_name', jsonb_build_object('type', 'text'), 'metric_category', jsonb_build_object('type', 'text', 'required', true),
        'metric_key', jsonb_build_object('type', 'code', 'required', true), 'numeric_value', jsonb_build_object('type', 'numeric', 'required', true),
        'unit', jsonb_build_object('type', 'text', 'required', true), 'currency_code', jsonb_build_object('type', 'code'),
        'reference_period', jsonb_build_object('type', 'text', 'required', true))),
    'career_outcomes', jsonb_build_object('target_table', 'destination.career_outcomes', 'apply', 'staged for review', 'key', jsonb_build_array('occupation_scheme', 'occupation_code', 'geography_level', 'state_code', 'reference_period'),
      'fields', jsonb_build_object(
        'occupation_scheme', jsonb_build_object('type', 'code', 'required', true), 'occupation_code', jsonb_build_object('type', 'code', 'required', true),
        'occupation_title', jsonb_build_object('type', 'text', 'required', true), 'geography_level', jsonb_build_object('type', 'code'),
        'state_code', jsonb_build_object('type', 'code'), 'median_salary', jsonb_build_object('type', 'currency_amount'), 'salary_currency', jsonb_build_object('type', 'code'),
        'salary_period', jsonb_build_object('type', 'text'), 'employment_rate_pct', jsonb_build_object('type', 'numeric'), 'job_outlook_rating', jsonb_build_object('type', 'text'),
        'skill_shortage_status', jsonb_build_object('type', 'text'), 'reference_period', jsonb_build_object('type', 'text'))),
    'scholarships', jsonb_build_object('target_table', 'pipeline.scholarship_source_records', 'apply', 'staged for review', 'key', jsonb_build_array('source_record_id'),
      'fields', jsonb_build_object(
        'source_record_id', jsonb_build_object('type', 'code', 'required', true), 'title', jsonb_build_object('type', 'text', 'required', true),
        'url', jsonb_build_object('type', 'url', 'required', true), 'provider_name', jsonb_build_object('type', 'text'), 'provider_code', jsonb_build_object('type', 'code'),
        'amount', jsonb_build_object('type', 'currency_amount'), 'currency_code', jsonb_build_object('type', 'code'), 'open_date', jsonb_build_object('type', 'date'),
        'close_date', jsonb_build_object('type', 'date'), 'study_level', jsonb_build_object('type', 'text'), 'eligibility', jsonb_build_object('type', 'text'))))
$function$;
comment on function security.layer1_parser_targets_v1() is 'Wave 2: for each Layer 1 target record type, the table its rows reach, the apply path, the key and the only fields an AI-built parser spec may name.';

-- 3. the spec check
create or replace function security.layer1_parser_spec_validate_v1(p_spec jsonb, p_record_type text, p_columns jsonb default null)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  e text[] := '{}'; t jsonb; f jsonb; tr jsonb; k text; v_targets text[] := '{}'; v_cols text[]; v_n int := 0;
  v_formats constant text[] := array['csv', 'xlsx', 'json', 'html_table'];
  v_types constant text[] := array['text', 'code', 'integer', 'numeric', 'currency_amount', 'date', 'boolean', 'url'];
  v_ops constant text[] := array['trim', 'upper', 'lower', 'strip_currency', 'date_format', 'default', 'map_values', 'first_token'];
  v_dates constant text[] := array['YYYY-MM-DD', 'DD/MM/YYYY', 'MM/DD/YYYY', 'D MMM YYYY', 'DD-MM-YYYY', 'YYYY/MM/DD'];
begin
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' then return jsonb_build_object('ok', false, 'errors', jsonb_build_array('The parser spec must be a JSON object.')); end if;
  if pg_column_size(p_spec) > 200000 then return jsonb_build_object('ok', false, 'errors', jsonb_build_array('The parser spec is larger than 200 KB.')); end if; -- fixed: input-safety bound (Mapper Contract v1.1)
  t := security.layer1_parser_targets_v1() -> p_record_type;
  if t is null then return jsonb_build_object('ok', false, 'errors', jsonb_build_array(format('Unknown target record type "%s".', p_record_type))); end if;
  for k in select jsonb_object_keys(p_spec) loop
    if k <> all (array['spec_version', 'record_type', 'target_table', 'format', 'source', 'expected_headers', 'fields', 'unique_key', 'attribution_text', 'evidence', 'currency']) then
      e := e || format('Unknown key "%s" in the spec.', k);
    end if;
  end loop;
  if p_spec->'spec_version' is distinct from to_jsonb(1) then e := e || 'spec_version must be 1.'::text; end if;
  if p_spec->>'record_type' is distinct from p_record_type then e := e || format('record_type must be "%s".', p_record_type); end if;
  if p_spec->>'target_table' is distinct from t->>'target_table' then e := e || format('target_table must be "%s" for this record type.', t->>'target_table'); end if;
  if coalesce(p_spec->>'format', '') <> all (v_formats) then e := e || 'format must be csv, xlsx, json or html_table.'::text; end if;
  if coalesce(btrim(p_spec->>'attribution_text'), '') = '' then e := e || 'attribution_text is required (shown beside every value).'::text; end if;
  if p_spec ? 'evidence' and p_spec->'evidence' is distinct from jsonb_build_object('bind', 'source_file') then e := e || 'evidence must be {"bind": "source_file"}.'::text; end if;
  if p_spec ? 'currency' and coalesce(p_spec->>'currency', '') !~ '^[A-Z]{3}$' then e := e || 'currency must be a three-letter code.'::text; end if;
  -- source: where the rows are
  if p_spec ? 'source' then
    if jsonb_typeof(p_spec->'source') <> 'object' then e := e || 'source must be an object.'::text;
    else
      for k in select jsonb_object_keys(p_spec->'source') loop
        if k <> all (array['sheet', 'header_row', 'rows_path', 'delimiter', 'table_index']) then e := e || format('Unknown key "%s" in source.', k); end if;
      end loop;
      if p_spec->'source' ? 'header_row' and not coalesce(case when jsonb_typeof(p_spec->'source'->'header_row') = 'number' then (p_spec->'source'->>'header_row')::numeric between 1 and 200 end, false) then e := e || 'source.header_row must be a row number from 1 to 200.'::text; end if; -- fixed: input-safety bound
      if p_spec->'source' ? 'rows_path' and coalesce(p_spec->'source'->>'rows_path', '') !~ '^\$(\.[A-Za-z_][A-Za-z0-9_]*(\[\*\])?){0,8}$' then e := e || 'source.rows_path must be a simple path such as $.data[*] (names and [*] only).'::text; end if;
      if p_spec->'source' ? 'delimiter' and coalesce(p_spec->'source'->>'delimiter', '') <> all (array[',', ';', '|', E'\t']) then e := e || 'source.delimiter must be a comma, semicolon, bar or tab.'::text; end if;
      if p_spec->'source' ? 'table_index' and not coalesce(case when jsonb_typeof(p_spec->'source'->'table_index') = 'number' then (p_spec->'source'->>'table_index')::numeric between 0 and 50 end, false) then e := e || 'source.table_index must be from 0 to 50.'::text; end if; -- fixed: input-safety bound
      if p_spec->'source' ? 'sheet' and length(coalesce(p_spec->'source'->>'sheet', '')) not between 1 and 100 then e := e || 'source.sheet must name a sheet.'::text; end if; -- fixed: input-safety bound
    end if;
  end if;
  -- fields
  if jsonb_typeof(p_spec->'fields') <> 'array' or jsonb_array_length(p_spec->'fields') = 0 then
    e := e || 'fields must be a non-empty list.'::text;
  elsif jsonb_array_length(p_spec->'fields') > 300 then
    e := e || 'fields may hold 300 entries at most.'::text; -- fixed: input-safety bound
  else
    for f in select value from jsonb_array_elements(p_spec->'fields') loop
      v_n := v_n + 1;
      if jsonb_typeof(f) <> 'object' then e := e || format('Field %s is not an object.', v_n); continue; end if;
      for k in select jsonb_object_keys(f) loop
        if k <> all (array['source', 'target', 'type', 'required', 'transforms']) then e := e || format('Unknown key "%s" in field %s.', k, v_n); end if;
      end loop;
      if coalesce(btrim(f->>'source'), '') = '' or length(f->>'source') > 200 then e := e || format('Field %s needs its source column or key.', v_n); end if; -- fixed: input-safety bound
      if not (t->'fields' ? coalesce(f->>'target', '')) then e := e || format('Field %s: target "%s" is not allowed for %s.', v_n, coalesce(f->>'target', ''), p_record_type);
      elsif (f->>'target') = any (v_targets) then e := e || format('Target "%s" is mapped twice.', f->>'target');
      else v_targets := v_targets || (f->>'target'); end if;
      if coalesce(f->>'type', '') <> all (v_types) then e := e || format('Field %s: type must be one of %s.', v_n, array_to_string(v_types, ', '));
      elsif t->'fields' ? coalesce(f->>'target', '') and f->>'type' <> t->'fields'->(f->>'target')->>'type' and not (f->>'type' in ('numeric', 'currency_amount', 'integer') and t->'fields'->(f->>'target')->>'type' in ('numeric', 'currency_amount', 'integer')) then
        e := e || format('Field %s: %s is a %s field.', v_n, f->>'target', t->'fields'->(f->>'target')->>'type');
      end if;
      if f ? 'required' and jsonb_typeof(f->'required') <> 'boolean' then e := e || format('Field %s: required must be true or false.', v_n); end if;
      if f ? 'transforms' then
        if jsonb_typeof(f->'transforms') <> 'array' or jsonb_array_length(f->'transforms') > 8 then e := e || format('Field %s: transforms must be a list of 8 at most.', v_n); -- fixed: input-safety bound
        else
          for tr in select value from jsonb_array_elements(f->'transforms') loop
            if jsonb_typeof(tr) <> 'object' or coalesce(tr->>'op', '') <> all (v_ops) then e := e || format('Field %s: transform must be one of %s.', v_n, array_to_string(v_ops, ', ')); continue; end if;
            for k in select jsonb_object_keys(tr) loop
              if k <> all (array['op', 'arg']) then e := e || format('Field %s: unknown key "%s" in a transform.', v_n, k); end if;
            end loop;
            if tr->>'op' = 'date_format' and coalesce(tr->>'arg', '') <> all (v_dates) then e := e || format('Field %s: date_format must be one of %s.', v_n, array_to_string(v_dates, ', ')); end if;
            if tr->>'op' = 'default' and (jsonb_typeof(tr->'arg') <> 'string' or length(tr->>'arg') > 200) then e := e || format('Field %s: default needs a short text value.', v_n); end if; -- fixed: input-safety bound
            if tr->>'op' = 'map_values' and (jsonb_typeof(tr->'arg') <> 'object' or (select count(*) from jsonb_each(tr->'arg')) > 200
                                              or exists (select 1 from jsonb_each(tr->'arg') x where jsonb_typeof(x.value) <> 'string')) then
              e := e || format('Field %s: map_values needs an object of text to text (200 entries at most).', v_n); -- fixed: input-safety bound
            end if;
            if tr->>'op' in ('trim', 'upper', 'lower', 'strip_currency', 'first_token') and tr ? 'arg' then e := e || format('Field %s: %s takes no argument.', v_n, tr->>'op'); end if;
          end loop;
        end if;
      end if;
    end loop;
    -- every required target of the record type is mapped
    for k in select x.key from jsonb_each(t->'fields') x where coalesce((x.value->>'required')::boolean, false) loop
      if k <> all (v_targets) then e := e || format('Required target "%s" is not mapped.', k); end if;
    end loop;
  end if;
  -- unique key: mapped targets, and it covers the record type's key
  if jsonb_typeof(p_spec->'unique_key') <> 'array' or jsonb_array_length(p_spec->'unique_key') = 0 then
    e := e || 'unique_key must list the mapped fields that identify a row.'::text;
  else
    for k in select jsonb_array_elements_text(p_spec->'unique_key') loop
      if k <> all (v_targets) then e := e || format('unique_key names "%s", which is not a mapped target.', k); end if;
    end loop;
    for k in select jsonb_array_elements_text(t->'key') loop
      if k = any (v_targets) and not (p_spec->'unique_key' ? k) then e := e || format('unique_key must include "%s".', k); end if;
    end loop;
  end if;
  -- expected headers: what drift is checked against; they must be in the sample when one is given
  if p_spec ? 'expected_headers' then
    if jsonb_typeof(p_spec->'expected_headers') <> 'array' or jsonb_array_length(p_spec->'expected_headers') > 300 then e := e || 'expected_headers must be a list of 300 at most.'::text; -- fixed: input-safety bound
    elsif jsonb_typeof(p_columns) = 'array' then
      v_cols := array(select btrim(x) from jsonb_array_elements_text(p_columns) x);
      for k in select btrim(x) from jsonb_array_elements_text(p_spec->'expected_headers') x loop
        if k <> all (v_cols) then e := e || format('Expected header "%s" is not in the sample.', k); end if;
      end loop;
    end if;
  elsif p_spec->>'format' in ('csv', 'xlsx', 'html_table') then
    e := e || 'expected_headers is required for csv, xlsx and html_table (layout drift is checked against it).'::text;
  end if;
  if jsonb_typeof(p_columns) = 'array' and jsonb_typeof(p_spec->'fields') = 'array' and p_spec->>'format' in ('csv', 'xlsx', 'html_table') then
    v_cols := array(select btrim(x) from jsonb_array_elements_text(p_columns) x);
    for k in select btrim(x->>'source') from jsonb_array_elements(p_spec->'fields') x where jsonb_typeof(x) = 'object' loop
      if k <> all (v_cols) then e := e || format('Source column "%s" is not in the sample.', k); end if;
    end loop;
  end if;
  return jsonb_build_object('ok', cardinality(e) = 0, 'errors', to_jsonb(e), 'target_table', t->>'target_table', 'apply', t->>'apply');
end $function$;
comment on function security.layer1_parser_spec_validate_v1(jsonb, text, jsonb) is 'Wave 2: the strict check of an AI-built Layer 1 parser spec (fixed lists of keys, formats, types, transforms; allowed targets per record type; unique key; attribution; headers against the sample).';

-- 4. service functions for the mapper
create or replace function public.svc_layer1_parser_spec_validate_v1(p_spec jsonb, p_record_type text, p_columns jsonb default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return security.layer1_parser_spec_validate_v1(p_spec, p_record_type, p_columns)
         || jsonb_build_object('targets', security.layer1_parser_targets_v1() -> p_record_type);
end $function$;
comment on function public.svc_layer1_parser_spec_validate_v1(jsonb, text, jsonb) is 'Wave 2: the parser spec check and the allowed targets of a record type, for layer1-ai-induction-mapper and the Layer 1 runner.';

create or replace function public.svc_layer1_mapper_call_v1(p_user uuid, p_detail jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_limit int := security.pipeline_num_v1('layer1.induction_mapper_calls_per_day', 200)::int; v_today int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select count(*) into v_today from pipeline.admin_control_events e
   where e.area = 'layer1' and e.action = 'ai_induction_map'
     and (e.created_at at time zone 'Australia/Sydney')::date = (now() at time zone 'Australia/Sydney')::date;
  if v_today >= v_limit then return jsonb_build_object('allowed', false, 'today', v_today, 'limit', v_limit); end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', 'ai_induction_map', coalesce(p_detail->>'induction_id', p_detail->>'source_id', 'mapper'), coalesce(p_detail, '{}'::jsonb), p_user);
  return jsonb_build_object('allowed', true, 'today', v_today + 1, 'limit', v_limit);
end $function$;
comment on function public.svc_layer1_mapper_call_v1(uuid, jsonb) is 'Wave 2: records one AI mapper call and refuses it once the daily limit (layer1.induction_mapper_calls_per_day) is reached.';

revoke all on function security.layer1_parser_targets_v1() from public, anon, authenticated;
revoke all on function security.layer1_parser_spec_validate_v1(jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function public.svc_layer1_parser_spec_validate_v1(jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function public.svc_layer1_mapper_call_v1(uuid, jsonb) from public, anon, authenticated;
grant execute on function security.layer1_parser_targets_v1() to service_role;
grant execute on function public.svc_layer1_parser_spec_validate_v1(jsonb, text, jsonb) to service_role;
grant execute on function public.svc_layer1_mapper_call_v1(uuid, jsonb) to service_role;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, introduced_in)
select v.kind, v.name, v.layer, 'Layer 1 register', v.purpose, 'active', '20261117221000'
  from (values
    ('edge_function', 'layer1-ai-induction-mapper', 'L1 register', 'Wave 2: AI Auto-Map for the induction wizard (Mapper Contract v1.1): field and category suggestions and a validated parser spec; writes nothing'),
    ('function', 'security.layer1_parser_spec_validate_v1', 'Layer 1', 'Wave 2: strict check of an AI-built parser spec'),
    ('function', 'security.layer1_parser_targets_v1', 'Layer 1', 'Wave 2: allowed targets per record type'),
    ('function', 'public.svc_layer1_parser_spec_validate_v1', 'Layer 1', 'Wave 2: spec check for the mapper and the runner'),
    ('function', 'public.svc_layer1_mapper_call_v1', 'Layer 1', 'Wave 2: mapper call log and daily limit')
  ) v(kind, name, layer, purpose)
 where not exists (select 1 from pipeline.component_register r where r.kind = v.kind and r.name = v.name);

-- post-checks: every record type has targets, and a good and a bad spec are told apart
do $$
declare v_good jsonb; v_bad jsonb;
begin
  if (select count(*) from jsonb_array_elements(security.layer1_record_types_v1()) t where not (security.layer1_parser_targets_v1() ? (t->>'key'))) > 0 then
    raise exception 'post-check: a record type has no targets';
  end if;
  v_good := security.layer1_parser_spec_validate_v1(jsonb_build_object('spec_version', 1, 'record_type', 'provider_register', 'target_table', 'catalogue.providers', 'format', 'csv',
              'expected_headers', jsonb_build_array('Code', 'Name'), 'attribution_text', 'Source: register',
              'fields', jsonb_build_array(jsonb_build_object('source', 'Code', 'target', 'provider_code', 'type', 'code', 'transforms', jsonb_build_array(jsonb_build_object('op', 'upper'))),
                                          jsonb_build_object('source', 'Name', 'target', 'provider_name', 'type', 'text')),
              'unique_key', jsonb_build_array('provider_code')), 'provider_register', jsonb_build_array('Code', 'Name'));
  if not (v_good->>'ok')::boolean then raise exception 'post-check: a valid spec was refused: %', v_good->'errors'; end if;
  v_bad := security.layer1_parser_spec_validate_v1(jsonb_build_object('spec_version', 1, 'record_type', 'provider_register', 'target_table', 'catalogue.providers', 'format', 'csv',
              'sql', 'drop table x', 'attribution_text', 'x', 'fields', jsonb_build_array(jsonb_build_object('source', 'Code', 'target', 'password', 'type', 'code')),
              'unique_key', jsonb_build_array('provider_code')), 'provider_register', null);
  if (v_bad->>'ok')::boolean or jsonb_array_length(v_bad->'errors') < 3 then raise exception 'post-check: an invalid spec was accepted'; end if;
end $$;
