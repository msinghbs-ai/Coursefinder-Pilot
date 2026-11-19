CREATE OR REPLACE FUNCTION public.website_v3_provider(p_provider_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v2_provider(p_provider_id); v_pid uuid;
begin
  if jsonb_typeof(v->'item') = 'object' then
    v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item'));
    select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_provider_id)) limit 1;
    if v ? 'item' and (v->'item') ? 'entry_matrix' then v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(v_pid, null)); end if;
  end if;
  return v;
end $function$
