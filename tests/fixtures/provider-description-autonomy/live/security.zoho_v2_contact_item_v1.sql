CREATE OR REPLACE FUNCTION security.zoho_v2_contact_item_v1(p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if p_key like 'pt:%' then
    select jsonb_build_object('contact_id', p_key, 'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
             'provider_name', coalesce(p.display_name, p.canonical_name),
             'type', case cp.kind when 'regulatory_peo' then 'head_of_institution' when 'public_general' then 'general' else cp.kind end,
             'name', cp.name, 'title', cp.title, 'team', null, 'email', cp.email, 'phone', cp.phone,
             'source', case cp.source when 'cricos' then 'CRICOS register' when 'provider_site' then 'Provider website' else cp.source end,
             'source_url', cp.source_url, 'checked_at', cp.observed_at)
      into v
      from pipeline.provider_contact_points cp join catalogue.providers p on p.id = cp.provider_id
     where cp.id::text = substr(p_key, 4) and cp.is_current and p.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  elsif p_key like 'pc:%' then
    select jsonb_build_object('contact_id', p_key, 'provider_id', p.stable_key, 'cricos_provider_code', security.zoho_v2_provider_cricos_v1(p.id),
             'provider_name', coalesce(p.display_name, p.canonical_name),
             'type', case pc.record_type when 'named_staff' then 'staff' when 'team_contact' then 'team' else pc.record_type end,
             'name', cv.full_name, 'title', cv.job_title, 'team', cv.team_name, 'email', cv.work_email, 'phone', cv.work_phone,
             'source', coalesce(cv.source_class, 'Contact list'), 'source_url', cv.source_url, 'checked_at', coalesce(cv.verified_on::timestamptz, cv.created_at))
      into v
      from pipeline.provider_contacts pc join pipeline.provider_contact_versions cv on cv.id = pc.current_version_id
      join catalogue.providers p on p.id = pc.provider_id
     where pc.id::text = substr(p_key, 4) and pc.lifecycle_status = 'active' and pc.deleted_at is null and p.lifecycle_status = 'active'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id);
  end if;
  return v;
end $function$
;

