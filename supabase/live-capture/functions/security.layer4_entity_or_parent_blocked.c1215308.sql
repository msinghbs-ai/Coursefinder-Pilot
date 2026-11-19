CREATE OR REPLACE FUNCTION security.layer4_entity_or_parent_blocked(p_entity_type text, p_entity_id uuid, p_block_scope text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'scholarship', 'pipeline'
AS $function$
declare v_type text:=lower(btrim(coalesce(p_entity_type,''))); v_provider uuid;
begin
  if p_block_scope not in ('operational','publication','search','data_quality_quarantine') then
    raise exception 'invalid block scope' using errcode='22023';
  end if;
  if exists(
    select 1 from security.layer4_active_blocks b
    where b.entity_type=v_type and b.entity_id=p_entity_id and b.block_scope=p_block_scope
  ) then return true; end if;

  if v_type='course' then
    select provider_id into v_provider from catalogue.courses where id=p_entity_id;
  elsif v_type='campus' then
    select provider_id into v_provider from catalogue.campuses where id=p_entity_id;
  elsif v_type='scholarship' then
    select provider_id into v_provider from scholarship.scholarships where id=p_entity_id;
  elsif v_type='provider_contact' then
    select provider_id into v_provider from pipeline.provider_contact_observations where id=p_entity_id;
  end if;

  return v_provider is not null and exists(
    select 1 from security.layer4_active_blocks b
    where b.entity_type='provider' and b.entity_id=v_provider and b.block_scope=p_block_scope
  );
end $function$
