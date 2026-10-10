CREATE OR REPLACE FUNCTION public.admin_course_edit(p_course_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_src uuid; v_c catalogue.courses%rowtype; v_field text; v_before jsonb; v_after jsonb;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), ''); v_url text; x jsonb; v_test uuid; v_amount numeric; v_val jsonb;
        v_keep uuid[] := '{}'; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_c from catalogue.courses where id = p_course_id;
  if v_c.id is null then raise exception 'course not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  select id into v_src from pipeline.sources where source_type = 'manual_entry' limit 1;

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_title','description','duration_value','duration_unit','delivery_mode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'duration_value' and v_val is not null and v_val <> 'null'::jsonb and not ((v_val #>> '{}') ~ '^[0-9]+(\.[0-9]+)?$') then raise exception 'duration must be a number'; end if;
    v_before := to_jsonb(v_c)->v_field;
    update catalogue.courses c set display_title = r.display_title, description = r.description, duration_value = r.duration_value,
           duration_unit = r.duration_unit, delivery_mode = r.delivery_mode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.courses x0 where x0.id = p_course_id) r
     where c.id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_official_url' then
    v_field := 'official_url'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active' and url <> v_url;
    insert into catalogue.course_links(course_id, link_type, url, label, is_primary, status, source_id, confidence, last_verified_at)
    values (p_course_id, 'official_course', v_url, 'Official course page', true, 'active', v_src, 1, now())
    on conflict (course_id, link_type, url) do update set status = 'active', is_primary = true, source_id = v_src, confidence = 1,
           last_verified_at = now(), updated_at = now(), evidence_id = null;
    update catalogue.courses set course_url = v_url, updated_at = now() where id = p_course_id;
    insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, bound_at, next_read_at, read_attempts)
    values (p_course_id, v_c.provider_id, v_url, 'manual', 'bound', now(), now(), 0)
    on conflict (course_id) do update set url = excluded.url, basis = 'manual', status = 'bound', bound_at = now(), score = null, runner_up = null,
           read_status = null, read_at = null, http_status = null, fetched_via = null, identity_basis = null, evidence_id = null, candidates = null,
           leased_until = null, read_attempts = 0, next_read_at = now();
    update pipeline.course_link_search set state = 'verified', bound_url = v_url, done_at = now() where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'value');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'value');
    v_after := to_jsonb(v_url);

  elsif p_action = 'remove_official_url' then
    v_field := 'official_url';
    select jsonb_agg(url) into v_before from catalogue.course_links where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.course_links set status = 'inactive', is_primary = false, updated_at = now()
     where course_id = p_course_id and link_type = 'official_course' and status = 'active';
    update catalogue.courses set course_url = null, updated_at = now() where id = p_course_id;
    update pipeline.coverage_course_pages set status = 'mismatch', basis = 'manual', leased_until = null where course_id = p_course_id;
    delete from pipeline.course_link_search where course_id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'official_url', 'removed');
    perform security.manual_lock_set('course', p_course_id, 'course_url', 'removed');

  elsif p_action = 'set_intakes' then
    v_field := 'intakes';
    if jsonb_typeof(p_args->'intakes') <> 'array' or jsonb_array_length(p_args->'intakes') = 0 then raise exception 'add at least one intake'; end if;
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year, 'start_date', start_date)) into v_before
      from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    for x in select * from jsonb_array_elements(p_args->'intakes') loop
      if nullif(btrim(coalesce(x->>'label', '')), '') is null then raise exception 'each intake needs a name, for example February'; end if;
      insert into catalogue.course_intakes(course_id, intake_year, intake_label, start_date, status, source_id, confidence, source_intake_key)
      values (p_course_id, nullif(x->>'year', '')::int, btrim(x->>'label'), nullif(x->>'start_date', '')::date, 'active', v_src, 1,
              'manual:' || lower(btrim(x->>'label')) || ':' || coalesce(nullif(x->>'year', ''), '') || ':' || coalesce(nullif(x->>'start_date', ''), ''))
      on conflict (course_id, source_id, source_intake_key) where source_id is not null and source_intake_key is not null
      do update set status = 'active', intake_year = excluded.intake_year, start_date = excluded.start_date, confidence = 1;
    end loop;
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'value');
    v_after := p_args->'intakes';

  elsif p_action = 'remove_intakes' then
    v_field := 'intakes';
    select jsonb_agg(jsonb_build_object('label', intake_label, 'year', intake_year)) into v_before from catalogue.course_intakes where course_id = p_course_id and status = 'active';
    update catalogue.course_intakes set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'intakes', 'removed');

  elsif p_action = 'set_english' then
    v_field := 'english';
    if jsonb_typeof(p_args->'tests') <> 'array' or jsonb_array_length(p_args->'tests') = 0 then raise exception 'add at least one English test score'; end if;
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score, 'components', e.component_scores)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    for x in select * from jsonb_array_elements(p_args->'tests') loop
      select id into v_test from ref.english_tests where code = x->>'test';
      if v_test is null then raise exception 'unknown English test %', x->>'test'; end if;
      if (x->>'overall') is null or (x->>'overall') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter an overall score for %', x->>'test'; end if;
      insert into catalogue.course_english_requirements(course_id, english_test_id, overall_score, component_scores, notes, source_id, evidence_id, confidence, source_requirement_key, status, last_verified_at)
      values (p_course_id, v_test, (x->>'overall')::numeric, coalesce(x->'components', '{}'::jsonb), 'Manual entry', v_src, null, 1, 'manual:' || lower(x->>'test'), 'active', now())
      on conflict (course_id, english_test_id) do update set overall_score = excluded.overall_score, component_scores = excluded.component_scores,
             notes = 'Manual entry', source_id = v_src, evidence_id = null, confidence = 1, source_requirement_key = excluded.source_requirement_key,
             status = 'active', last_verified_at = now();
      v_keep := v_keep || v_test;
    end loop;
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active' and not (english_test_id = any(v_keep));
    perform security.manual_lock_set('course', p_course_id, 'english', 'value');
    v_after := p_args->'tests';

  elsif p_action = 'remove_english' then
    v_field := 'english';
    select jsonb_agg(jsonb_build_object('test', t.code, 'overall', e.overall_score)) into v_before
      from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id where e.course_id = p_course_id and e.status = 'active';
    update catalogue.course_english_requirements set status = 'inactive' where course_id = p_course_id and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'english', 'removed');

  elsif p_action = 'set_tuition' then
    v_field := 'tuition';
    if coalesce(p_args->>'amount', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p_args->>'amount')::numeric < 100 then raise exception 'enter the fee as a number, for example 45000'; end if;
    if coalesce(p_args->>'basis', 'annual') not in ('annual','total_indicative','per_semester','per_trimester') then raise exception 'choose per year, per semester, per trimester or whole course'; end if;
    v_amount := (p_args->>'amount')::numeric;
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'superseded', updated_at = now(),
           notes = coalesce(notes, '') || ' | superseded by a manual entry ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, notes, source_id, confidence, source_fee_key, status, last_verified_at)
    values (p_course_id, nullif(p_args->>'fee_year', '')::int, 'international', 'provider_current_tuition', v_amount, coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'),
            coalesce(p_args->>'basis', 'annual'), 'Manual entry', v_src, 1, 'manual:' || extract(epoch from clock_timestamp())::bigint, 'active', now());
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'value');
    v_after := jsonb_build_object('amount', v_amount, 'year', nullif(p_args->>'fee_year', ''), 'basis', coalesce(p_args->>'basis', 'annual'), 'currency', coalesce(nullif(p_args->>'currency', ''), (select k.default_currency_code::text from catalogue.providers pv join ref.countries k on k.id = pv.country_id where pv.id = v_c.provider_id), 'AUD'));

  elsif p_action = 'remove_tuition' then
    v_field := 'tuition';
    select jsonb_agg(jsonb_build_object('amount', amount, 'year', fee_year, 'basis', basis)) into v_before
      from catalogue.course_fees where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    update catalogue.course_fees set status = 'inactive', updated_at = now(), notes = coalesce(notes, '') || ' | removed by hand ' || to_char(now(), 'YYYY-MM-DD')
     where course_id = p_course_id and fee_type = 'provider_current_tuition' and status = 'active';
    perform security.manual_lock_set('course', p_course_id, 'tuition', 'removed');

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'course' and entity_id = p_course_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'course' and entity_id = p_course_id and (field = v_field or (v_field = 'official_url' and field = 'course_url'));
    if v_field = 'official_url' then
      update pipeline.coverage_course_pages set basis = 'released' where course_id = p_course_id and basis = 'manual';
    end if;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_c.lifecycle_status);
    update catalogue.courses set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_course_id;
    perform security.manual_lock_set('course', p_course_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  if v_field in ('official_url','intakes','english','tuition') and p_action <> 'release' then
    perform security.manual_close_layer4(p_course_id, v_field);
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('course', p_course_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  perform search.refresh_course_enrichment_scoped_v1(array[p_course_id], true);
  return public.admin_course_edit_read(p_course_id);
end $function$
