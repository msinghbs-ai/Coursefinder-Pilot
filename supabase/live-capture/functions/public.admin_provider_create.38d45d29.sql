CREATE OR REPLACE FUNCTION public.admin_provider_create(p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid := gen_random_uuid(); v_name text := nullif(btrim(coalesce(p_args->>'name', '')), ''); v_country uuid := nullif(p_args->>'country_id', '')::uuid;
        v_web text := nullif(btrim(coalesce(p_args->>'website', '')), '');
begin
  if auth.uid() is null or security.current_role_rank() < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  if v_name is null then raise exception 'enter the provider name'; end if;
  if v_country is null or not exists (select 1 from ref.countries where id = v_country) then raise exception 'choose the country'; end if;
  if v_web is not null and v_web !~* '^https?://[^\s/]+\.[^\s]+$' then raise exception 'enter a full web address starting with https://'; end if;
  if exists (select 1 from catalogue.providers where lower(canonical_name) = lower(v_name) and country_id = v_country) then raise exception 'a provider with this name already exists in that country'; end if;
  perform set_config('cf.manual_edit', 'on', true);
  insert into catalogue.providers(id, stable_key, canonical_name, display_name, country_id, subdivision_id, website, primary_city, lifecycle_status)
  values (v_id, 'manual:' || v_id, v_name, v_name, v_country, nullif(p_args->>'subdivision_id', '')::uuid, v_web, nullif(btrim(coalesce(p_args->>'city', '')), ''), 'active');
  if v_web is not null then
    insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at) values (v_id, v_web, 'pending', 0, now(), now())
    on conflict (provider_id) do nothing;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, after, reason, actor)
  values ('provider', v_id, null, 'create', p_args, nullif(btrim(coalesce(p_args->>'reason', '')), ''), auth.uid());
  return public.admin_provider_edit_read(v_id);
end $function$
