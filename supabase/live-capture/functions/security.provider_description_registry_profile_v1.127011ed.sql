CREATE OR REPLACE FUNCTION security.provider_description_registry_profile_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; reg record; tpl text; v_country text; v_type text; v_tcode text; v_region text; v_city text; v_loc text; v_name text; v_art text;
        v_levels text[]; v_fields text[]; v_max int := security.pipeline_num_v1('pdesc.registry_offerings_max', 3)::int; v_min int := security.pipeline_num_v1('pdesc.registry_min_facts', 3)::int;
        v_facts jsonb := '[]'::jsonb; v_sent jsonb := '[]'::jsonb; s1 text; s2 text; s3 text; v_text text; v_ev record; v_have text[] := '{}'; v_asof timestamptz;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'No such provider.'); end if;
  select k.name into v_country from ref.countries k where k.id = p.country_id;
  select t.code, t.name into v_tcode, v_type from ref.provider_types t where t.id = p.provider_type_id;
  select s.name into v_region from ref.subdivisions s where s.id = p.subdivision_id;
  select r.* into reg from catalogue.provider_registrations r where r.provider_id = p.id and r.status = 'active' and r.evidence_id is not null order by r.checked_at desc nulls last, r.id limit 1;
  if reg.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The provider has no active register listing with stored evidence.'); end if;
  select a.id, a.source_url, a.content_hash, coalesce(a.captured_at, a.created_at) captured_at into v_ev from pipeline.evidence_artifacts a where a.id = reg.evidence_id;
  if v_ev.id is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The register listing''s evidence is not stored.'); end if;
  select t.register_sentence into tpl from pipeline.provider_description_registry_templates t where t.scheme = reg.registration_scheme and t.active;
  if tpl is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'There is no profile wording for register scheme ' || reg.registration_scheme || '.'); end if;
  v_name := coalesce(security.pdesc_clean_name_v1(p.display_name), security.pdesc_clean_name_v1(p.canonical_name));
  if v_name is null then return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The provider has no usable name (a placeholder or page markup).'); end if;
  v_asof := coalesce(reg.checked_at, v_ev.captured_at);
  -- facts: each is a field of the verified record, with where it came from
  v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'register', 'field', 'catalogue.provider_registrations', 'value', reg.registration_scheme || ' ' || reg.registration_code || ' ' || reg.status,
      'source', 'register', 'registration_id', reg.id, 'evidence_id', reg.evidence_id, 'source_url', v_ev.source_url, 'source_hash', coalesce(v_ev.content_hash, v_ev.id::text), 'as_at', v_asof));
  v_have := v_have || 'register'::text;
  if v_tcode is not null and v_tcode <> 'other' and nullif(btrim(v_type), '') is not null then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'type', 'field', 'ref.provider_types.name', 'value', v_type, 'source', 'provider_record', 'provider_id', p.id, 'as_at', coalesce(p.provider_type_set_at, p.updated_at)));
    v_have := v_have || 'type'::text;
  end if;
  v_city := nullif(btrim(p.primary_city), '');
  if v_city is not null and v_city = upper(v_city) and length(v_city) >= security.pipeline_num_v1('pdesc.city_min_chars', 4)::int then v_city := initcap(lower(v_city)); end if;
  if v_city is not null and security.pdesc_machine_text_check_v1(p.id, v_city) is not null then v_city := null; end if; -- a "campus" or other refused word is not a city
  if v_city is not null and (position('?' in v_city) > 0 or position(chr(65533) in v_city) > 0) then v_city := null; end if; -- a city that lost a character ("Whang?rei") is not stated as a place
  v_loc := nullif(concat_ws(', ', v_city, nullif(btrim(v_region), ''), nullif(btrim(v_country), '')), '');
  if (v_city is not null or nullif(btrim(v_region), '') is not null) and v_loc is not null then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'location', 'field', 'catalogue.providers.primary_city, subdivision, country', 'value', v_loc, 'source', 'provider_record', 'provider_id', p.id, 'as_at', p.updated_at));
    v_have := v_have || 'location'::text;
  end if;
  select coalesce(array_agg(x.name order by x.name), '{}') into v_levels from (select distinct sl.name from catalogue.courses c join ref.study_levels sl on sl.id = c.study_level_id
     where c.provider_id = p.id and c.lifecycle_status = 'active' and nullif(btrim(sl.name), '') is not null order by sl.name limit v_max) x;
  select coalesce(array_agg(x.name order by x.name), '{}') into v_fields from (select distinct f.name from catalogue.courses c join ref.fields_of_study f on f.id = c.primary_field_id
     where c.provider_id = p.id and c.lifecycle_status = 'active' and nullif(btrim(f.name), '') is not null order by f.name limit v_max) x;
  if coalesce(array_length(v_levels, 1), 0) > 0 then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'levels', 'field', 'catalogue.courses.study_level_id (active courses)', 'value', to_jsonb(v_levels), 'source', 'catalogue', 'provider_id', p.id, 'as_at', now()));
    v_have := v_have || 'levels'::text;
  end if;
  if coalesce(array_length(v_fields, 1), 0) > 0 then
    v_facts := v_facts || jsonb_build_array(jsonb_build_object('key', 'fields', 'field', 'catalogue.courses.primary_field_id (active courses)', 'value', to_jsonb(v_fields), 'source', 'catalogue', 'provider_id', p.id, 'as_at', now()));
    v_have := v_have || 'fields'::text;
  end if;
  if coalesce(array_length(v_have, 1), 0) < v_min then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'facts_held', to_jsonb(v_have), 'facts_needed', v_min,
      'reason', format('%s verified fact(s) held (%s); %s needed for a useful, truthful profile.', coalesce(array_length(v_have, 1), 0), array_to_string(v_have, ', '), v_min));
  end if;
  -- sentences: wording only joins the verified facts
  v_art := case when v_type is null or lower(v_type) ~ '^(uni|use|eu|one|ubi)' then 'a' when lower(left(v_type, 1)) in ('a', 'e', 'i', 'o', 'u') then 'an' else 'a' end; -- "a university", "an agricultural college"
  s1 := case when 'type' = any (v_have) then v_name || ' is ' || v_art || ' ' || case when v_type ~ '^[A-Z][a-z]' then lower(left(v_type, 1)) || substr(v_type, 2) else v_type end || coalesce(' in ' || v_loc, '') || '.'
             else v_name || coalesce(' is located in ' || v_loc, ' is listed in this catalogue') || '.' end;
  s2 := replace(replace(tpl, '{name}', 'It'), '{code}', reg.registration_code);
  -- the second sentence reads "It is listed ..." / "It appears ..."; the template starts with the name, so the pronoun replaces it
  s3 := case when 'levels' = any (v_have) and 'fields' = any (v_have) then 'Its listed courses are at ' || regexp_replace(array_to_string(v_levels, ', '), ', ([^,]*)$', ' and \1') || ' levels, in fields including ' || regexp_replace(array_to_string(v_fields, ', '), ', ([^,]*)$', ' and \1') || '.'
             when 'levels' = any (v_have) then 'Its listed courses are at ' || regexp_replace(array_to_string(v_levels, ', '), ', ([^,]*)$', ' and \1') || ' levels.'
             when 'fields' = any (v_have) then 'Its listed courses are in fields including ' || regexp_replace(array_to_string(v_fields, ', '), ', ([^,]*)$', ' and \1') || '.' end;
  v_sent := jsonb_build_array(jsonb_build_object('text', s1, 'facts', (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array['type', 'location']) k where k = any (v_have))),
                              jsonb_build_object('text', s2, 'facts', jsonb_build_array('register')));
  if s3 is not null then v_sent := v_sent || jsonb_build_array(jsonb_build_object('text', s3, 'facts', (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array['levels', 'fields']) k where k = any (v_have)))); end if;
  v_text := concat_ws(' ', s1, s2, s3);
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or jsonb_array_length(v_sent) < security.pipeline_num_v1('pdesc.min_sentences', 2) or jsonb_array_length(v_sent) > security.pipeline_num_v1('pdesc.max_sentences', 5) then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The profile (' || length(v_text) || ' characters, ' || jsonb_array_length(v_sent) || ' sentences) is outside the description limits (pdesc.min_chars, min_sentences, max_sentences).'); end if;
  if length(v_text) > security.pipeline_num_v1('pdesc.max_chars', 900) then
    return jsonb_build_object('ok', false, 'rule', 'insufficient_verified_facts', 'reason', 'The profile is longer than the description limit (' || length(v_text) || ' characters).'); end if;
  return jsonb_build_object('ok', true, 'rule', 'registry_factual', 'tier', 'registry_factual', 'text', v_text, 'sentences', v_sent, 'facts', v_facts, 'evidence_id', reg.evidence_id, 'registration_id', reg.id,
    'source_url', v_ev.source_url, 'source_hash', coalesce(v_ev.content_hash, v_ev.id::text), 'captured_at', v_ev.captured_at, 'codes', jsonb_build_array(s2, reg.registration_code) || to_jsonb(coalesce(v_levels, '{}'::text[])) || to_jsonb(coalesce(v_fields, '{}'::text[])), 'profile_version', 'registry-profile-v1');
end $function$
