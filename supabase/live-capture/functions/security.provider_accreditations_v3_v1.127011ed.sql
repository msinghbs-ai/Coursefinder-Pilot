CREATE OR REPLACE FUNCTION security.provider_accreditations_v3_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('body_code', a.body_code, 'accredited_unit_name', a.accredited_unit_name, 'accredited_since', a.accredited_since,
                                                'expires_at', a.expires_at, 'source_url', a.source_url, 'verified_at', a.verified_at)
                            order by a.body_code, a.accredited_unit_name nulls first, a.id), '[]'::jsonb)
    from catalogue.provider_accreditations a
   where a.provider_id = p_provider and a.status = 'active' and (a.expires_at is null or a.expires_at >= current_date)
$function$
