CREATE OR REPLACE FUNCTION public.admin_scholarship_countries()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'insufficient role' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from security.scholarship_country_readiness_v1() x), '[]'::jsonb);
end $function$
