CREATE OR REPLACE FUNCTION public.admin_provider_edit(p_provider_id uuid, p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_p catalogue.providers%rowtype; v_field text; v_before jsonb; v_after jsonb; v_val jsonb; v_url text;
        v_reason text := nullif(btrim(coalesce(p_args->>'reason', '')), '');
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select * into v_p from catalogue.providers where id = p_provider_id;
  if v_p.id is null then raise exception 'provider not found'; end if;
  if p_action in ('archive','restore') and v_rank < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  perform set_config('cf.manual_edit', 'on', true);

  if p_action = 'set_core' then
    v_field := p_args->>'field';
    if v_field is null or v_field not in ('display_name','short_name','website','phone','email','description','primary_city','address_line1','postcode') then raise exception 'this field cannot be edited here'; end if;
    v_val := p_args->'value';
    if jsonb_typeof(v_val) = 'string' then v_val := to_jsonb(nullif(btrim(v_val #>> '{}'), '')); end if;
    if v_field = 'website' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    if v_field = 'email' and v_val is not null and v_val <> 'null'::jsonb and (v_val #>> '{}') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'enter a valid email address'; end if;
    v_before := to_jsonb(v_p)->v_field;
    update catalogue.providers p set display_name = r.display_name, short_name = r.short_name, website = r.website, phone = r.phone, email = r.email,
           description = r.description, primary_city = r.primary_city, address_line1 = r.address_line1, postcode = r.postcode, updated_at = now()
      from (select (jsonb_populate_record(x0, jsonb_build_object(v_field, v_val))).* from catalogue.providers x0 where x0.id = p_provider_id) r
     where p.id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, v_field, 'value');
    v_after := v_val;

  elsif p_action = 'set_course_finder' then
    v_field := 'course_finder'; v_url := btrim(coalesce(p_args->>'url', ''));
    if v_url !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
    select to_jsonb(d.website) into v_before from pipeline.coverage_provider_discovery d where d.provider_id = p_provider_id;
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
    values (p_provider_id, v_url, 'pending', 0, now(), now())
    on conflict (provider_id) do update set website = excluded.website, status = 'pending', attempts = 0, next_due_at = now(), leased_until = null,
           last_error = null, updated_at = now();
    v_after := to_jsonb(v_url);

  elsif p_action = 'release' then
    v_field := p_args->>'field';
    select to_jsonb(l) into v_before from pipeline.manual_locks l where entity = 'provider' and entity_id = p_provider_id and field = v_field;
    if v_before is null then raise exception 'nothing to release'; end if;
    delete from pipeline.manual_locks where entity = 'provider' and entity_id = p_provider_id and field = v_field;

  elsif p_action in ('archive','restore') then
    v_field := 'lifecycle_status'; v_before := to_jsonb(v_p.lifecycle_status);
    update catalogue.providers set lifecycle_status = case p_action when 'archive' then 'inactive' else 'active' end, updated_at = now() where id = p_provider_id;
    perform security.manual_lock_set('provider', p_provider_id, 'lifecycle_status', 'value');
    v_after := to_jsonb(case p_action when 'archive' then 'inactive' else 'active' end);

  else
    raise exception 'unknown action %', p_action;
  end if;

  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, v_field, p_action, v_before, v_after, v_reason, auth.uid());
  return public.admin_provider_edit_read(p_provider_id);
end $function$
