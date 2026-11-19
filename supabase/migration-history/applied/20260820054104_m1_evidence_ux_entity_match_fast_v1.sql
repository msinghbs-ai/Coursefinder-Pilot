-- Route all Evidence entity/provider filtering through the maintained derived link index.
create or replace function security.admin_evidence_matches_entity(
  p_evidence_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_provider_id uuid
)
returns boolean
language sql
stable
set search_path = pg_catalog, pipeline
as $$
  select case
    when nullif(trim(coalesce(p_entity_type,'')),'') is null
      and p_entity_id is null
      and p_provider_id is null then true
    else exists(
      select 1
      from pipeline.evidence_entity_links el
      where el.evidence_id=p_evidence_id
        and (nullif(trim(coalesce(p_entity_type,'')),'') is null or el.entity_type=lower(trim(p_entity_type)))
        and (p_entity_id is null or el.entity_id=p_entity_id)
        and (p_provider_id is null or el.provider_id=p_provider_id)
    )
  end
$$;
