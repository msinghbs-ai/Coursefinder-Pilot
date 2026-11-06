CREATE OR REPLACE FUNCTION public.website_v2_provider(p_provider_id text, p_edu_country text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_pid uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v_cc !~ '^[A-Z]{2}$' or not exists (select 1 from ref.countries k where k.iso_alpha2 = v_cc) then
    raise exception 'INVALID_INPUT: edu_country must be a known ISO 3166 alpha-2 country code' using errcode = '22023';
  end if;
  v := public.website_v2_provider(p_provider_id);
  if v ? 'error' then return v; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_provider_id)) limit 1;
  return jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v1(v_pid, v_cc));
end $function$

