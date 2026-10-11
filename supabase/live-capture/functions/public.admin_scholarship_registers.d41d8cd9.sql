CREATE OR REPLACE FUNCTION public.admin_scholarship_registers()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'insufficient role' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'code', r.code, 'country', r.country_code, 'name', r.name, 'role', r.role, 'status', r.status, 'url', r.url,
      'listings', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null),
      'matched', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.scholarship_id is not null),
      'handed_to_page_reader', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.handoff_status = 'handed_to_page_reader'),
      'off_provider_site', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.handoff_status = 'provider_page_off_provider_site'),
      'provider_unknown', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is null and l.scholarship_id is null and l.provider_id is null and l.detail_read_at is not null),
      'departed', (select count(*) from scholarship.register_listings l where l.register_code = r.code and l.departed_at is not null),
      'records', (select count(*) from scholarship.scholarships s where s.source_id = r.source_id and s.lifecycle_status = 'active'),
      'last_seen_at', (select max(last_seen_at) from scholarship.register_listings l where l.register_code = r.code)
    ) order by r.country_code, r.code) from scholarship.registers r), '[]'::jsonb);
end $function$
