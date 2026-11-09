CREATE OR REPLACE FUNCTION security.provider_university_groups(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'ref'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('code',replace(ic.code,'au_',''),'name',ic.name) order by ic.name),'[]'::jsonb)
    from catalogue.provider_collection_memberships m join ref.institution_collections ic on ic.id=m.collection_id
   where m.provider_id=p_provider_id and m.status='active' and ic.collection_type='university_group' and ic.status='active'
     and (m.valid_to is null or m.valid_to>=current_date)
$function$
