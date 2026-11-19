CREATE OR REPLACE FUNCTION security.provider_description_machine_blocked_v1(p_provider uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER COST 500
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v_find text;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null then return jsonb_build_object('rule', 'provider_not_live', 'reason', 'There is no such provider.'); end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')) then
    return jsonb_build_object('rule', 'manual_lock', 'reason', 'The description is locked by hand.'); end if;
  if nullif(btrim(p.description), '') is not null and security.provider_description_basic_profile_v1(p.id) is null then -- a register-fact profile is not a description held (pdesc.registry_upgrade_on); every check below still applies to it
    return jsonb_build_object('rule', 'description_already_held', 'reason', 'The provider already holds a description; the machine rule admits a first description only.'); end if;
  if nullif(btrim(p.description), '') is null and exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null) then
    return jsonb_build_object('rule', 'description_cleared_after_admission', 'reason', 'A machine description was admitted for this provider and the description has since been cleared by hand; a person decides the next one.'); end if;
  if exists (select 1 from pipeline.layer4_review_items li where li.entity_type = 'provider' and li.entity_id = p.id and li.field_code = 'provider_description' and li.status = 'rejected') then
    return jsonb_build_object('rule', 'prior_human_rejection', 'reason', 'A person rejected an earlier description for this provider.'); end if;
  if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is not null and coalesce(a.withdrawn_reason, '') not like 'Upgraded to a source-verified description%'
               and not exists (select 1 from pipeline.provider_description_machine_admissions b where b.provider_id = p.id and b.outcome = 'admitted' and b.created_at > a.withdrawn_at)) then
    return jsonb_build_object('rule', 'withdrawn_awaiting_review', 'reason', 'A machine description for this provider was withdrawn; a person decides the next one.'); end if;
  select f.check_code into v_find from pipeline.provider_identity_findings f where f.provider_id = p.id and f.state = 'open' order by f.check_code limit 1;
  if v_find is not null then return jsonb_build_object('rule', 'identity_' || v_find, 'reason', 'An open provider identity finding needs a person: ' || v_find); end if;
  if (nullif(btrim(p.canonical_name), '') is not null and security.pdesc_clean_name_v1(p.canonical_name) is null)
     or (nullif(btrim(p.display_name), '') is not null and security.pdesc_clean_name_v1(p.display_name) is null)
     or (security.pdesc_clean_name_v1(p.canonical_name) is null and security.pdesc_clean_name_v1(p.display_name) is null) then
    return jsonb_build_object('rule', 'name_not_clean', 'reason', 'A provider name is a placeholder, too short or still holds web-page markup, so the identity proof is not reliable; a person decides.'); end if;
  return null;
end $function$
