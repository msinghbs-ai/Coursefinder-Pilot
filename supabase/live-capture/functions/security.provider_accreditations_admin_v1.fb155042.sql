CREATE OR REPLACE FUNCTION security.provider_accreditations_admin_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- s780 (19 Nov 2026): Provider details › accreditations. Curator and above (rank 3+) see every row with its status, so rows under review show;
-- any other role sees what API v3 sends (security.provider_accreditations_v3_v1). Security definer: public.admin_read runs as the caller.
begin
  if coalesce(security.current_role_rank(), 0) >= 3 then
    return (select coalesce(jsonb_agg(jsonb_build_object('body_code', a.body_code, 'accredited_unit_name', a.accredited_unit_name, 'status', a.status,
                     'accredited_since', a.accredited_since, 'expires_at', a.expires_at, 'rating', a.rating, 'rating_period', a.rating_period,
                     'source_url', a.source_url, 'verified_at', a.verified_at) order by a.body_code, a.accredited_unit_name nulls first, a.id), '[]'::jsonb)
              from catalogue.provider_accreditations a where a.provider_id = p_provider_id);
  end if;
  return security.provider_accreditations_v3_v1(p_provider_id);
end $function$
