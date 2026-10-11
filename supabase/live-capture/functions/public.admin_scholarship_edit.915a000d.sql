CREATE OR REPLACE FUNCTION public.admin_scholarship_edit(p_scholarship_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_s scholarship.scholarships%rowtype; v_field text := p_args->>'field';
        v_val jsonb := p_args->'value'; v_txt text; v_before jsonb; v_after jsonb; v_locks text[];
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_s from scholarship.scholarships where id = p_scholarship_id;
  if v_s.id is null then raise exception 'scholarship not found'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  if p_action = 'set_core' then
    if v_field is null or v_field not in ('name','description','award_value_text','award_amount','award_percentage','application_open_date','application_close_date','source_url') then
      raise exception 'this field cannot be edited here'; end if;
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    v_txt := case when v_val is null or v_val = 'null'::jsonb then null else v_val #>> '{}' end;
    if v_field = 'name' and v_txt is null then raise exception 'a scholarship needs a name'; end if;
    if v_field = 'award_amount' and v_txt is not null and (v_txt !~ '^[0-9]+(\.[0-9]+)?$' or v_txt::numeric <= 0) then raise exception 'enter the award as a number, for example 5000'; end if;
    if v_field = 'award_percentage' and v_txt is not null and (v_txt !~ '^[0-9]+(\.[0-9]+)?$' or v_txt::numeric <= 0 or v_txt::numeric > 100) then raise exception 'enter a percentage between 1 and 100'; end if;
    if v_field in ('application_open_date','application_close_date') and v_txt is not null and v_txt !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'enter the date as dd/mm/yyyy'; end if;
    if v_field = 'source_url' and v_txt is not null and v_txt !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'enter the full address, starting with https://'; end if;
    v_before := to_jsonb(v_s)->v_field;
    if v_field = 'award_amount' then
      update scholarship.scholarships set award_amount = v_txt::numeric,
             award_value_type = case when v_txt is not null then 'fixed_amount' when award_percentage is not null then 'percentage' else award_value_type end,
             award_percentage = case when v_txt is not null then null else award_percentage end,
             award_currency_code = case when v_txt is not null then coalesce(award_currency_code, scholarship.provider_currency(provider_id)) else award_currency_code end, updated_at = now()
       where id = p_scholarship_id;
      v_locks := array['award_amount','award_percentage','award_value_type','award_currency_code'];
    elsif v_field = 'award_percentage' then
      update scholarship.scholarships set award_percentage = v_txt::numeric,
             award_value_type = case when v_txt is not null then 'percentage' when award_amount is not null then 'fixed_amount' else award_value_type end,
             award_amount = case when v_txt is not null then null else award_amount end, updated_at = now()
       where id = p_scholarship_id;
      v_locks := array['award_amount','award_percentage','award_value_type'];
    else
      update scholarship.scholarships s set name = r.name, description = r.description, award_value_text = r.award_value_text,
             application_open_date = r.application_open_date, application_close_date = r.application_close_date, source_url = r.source_url, updated_at = now()
        from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from scholarship.scholarships x0 where x0.id = p_scholarship_id) r
       where s.id = p_scholarship_id;
      v_locks := array[v_field];
    end if;
    perform security.manual_lock_set('scholarship', p_scholarship_id, f, 'value') from unnest(v_locks) f;
    v_after := v_val;
  elsif p_action = 'set_audience' then
    v_field := 'audience';
    v_txt := btrim(coalesce(p_args->>'value', ''));
    if v_txt not in ('international', 'domestic', 'international_and_domestic', 'not_stated') then raise exception 'choose who the scholarship is for'; end if;
    v_before := to_jsonb(v_s.audience);
    update scholarship.scholarships set audience = v_txt, updated_at = now() where id = p_scholarship_id;
    perform security.manual_lock_set('scholarship', p_scholarship_id, 'audience', 'value');
    v_after := to_jsonb(v_txt);
  elsif p_action = 'set_nationalities' then
    v_field := 'nationalities';
    if jsonb_typeof(p_args->'value') is distinct from 'array' then raise exception 'give a list of nationalities'; end if;
    if exists (select 1 from jsonb_array_elements_text(p_args->'value') c where not exists (select 1 from ref.nationality_terms t where t.code = c)) then raise exception 'unknown nationality'; end if;
    v_before := to_jsonb(v_s.nationalities);
    update scholarship.scholarships set nationalities = coalesce((select array_agg(distinct c order by c) from jsonb_array_elements_text(p_args->'value') c), '{}'), updated_at = now() where id = p_scholarship_id;
    perform security.manual_lock_set('scholarship', p_scholarship_id, 'nationalities', 'value');
    v_after := p_args->'value';
  elsif p_action = 'release' then
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'scholarship' and entity_id = p_scholarship_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'scholarship' and entity_id = p_scholarship_id
       and (field = v_field or (v_field in ('award_amount','award_percentage') and field in ('award_amount','award_percentage','award_value_type','award_currency_code')));
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('scholarship', p_scholarship_id, v_field, p_action, v_before, v_after, nullif(btrim(coalesce(p_args->>'reason','')),''), auth.uid());
  return (select jsonb_build_object('id', s.id, 'name', s.name, 'award_value_text', s.award_value_text, 'award_amount', s.award_amount,
            'award_percentage', s.award_percentage, 'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date,
            'source_url', s.source_url, 'audience', s.audience, 'nationalities', s.nationalities, 'value_label', scholarship.value_label(s.id), 'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id))
            from scholarship.scholarships s where s.id = p_scholarship_id);
end $function$
