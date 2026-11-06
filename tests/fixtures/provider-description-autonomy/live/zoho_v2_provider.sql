CREATE OR REPLACE FUNCTION public.zoho_v2_provider(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pid uuid; v jsonb; w jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if nullif(btrim(coalesce(p_identifier, '')), '') is null then raise exception 'INVALID_INPUT: provider_id or cricos_provider_code required' using errcode = '22023'; end if;
  select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_identifier)) limit 1;
  if v_pid is null then
    select pr.provider_id into v_pid from catalogue.provider_registrations pr where lower(pr.registration_scheme) = 'cricos' and upper(pr.registration_code) = upper(btrim(p_identifier)) limit 1;
  end if;
  v := case when v_pid is null then null else security.zoho_v2_provider_item_v1(v_pid) end;
  if v is null then return jsonb_build_object('api_version', 'zoho-v2', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  w := public.website_v2_provider(v->>'provider_id');  -- full detail (rankings with indicators, outcomes) where the provider has courses
  if w ? 'item' then v := (w->'item') || (v - 'logo' - 'rankings' - 'outcomes' - 'campuses'); end if;
  return jsonb_build_object('api_version', 'zoho-v2', 'item', v || jsonb_build_object(
    'campuses', coalesce((select jsonb_agg(security.zoho_v2_campus_item_v1(k.id) order by k.name) from catalogue.campuses k where k.provider_id = v_pid and coalesce(k.status, 'active') = 'active'), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(c order by c->>'type', c->>'name') from (
        select security.zoho_v2_contact_item_v1('pt:' || cp.id) c from pipeline.provider_contact_points cp where cp.provider_id = v_pid and cp.is_current
        union all select security.zoho_v2_contact_item_v1('pc:' || pc.id) from pipeline.provider_contacts pc where pc.provider_id = v_pid and pc.lifecycle_status = 'active' and pc.deleted_at is null) z where c is not null), '[]'::jsonb)));
end $function$
;

