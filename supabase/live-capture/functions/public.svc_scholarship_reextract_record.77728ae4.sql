CREATE OR REPLACE FUNCTION public.svc_scholarship_reextract_record(p_scholarship_id uuid, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v text[];
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  update pipeline.scholarship_pages
     set facts = facts || jsonb_build_object('criteria', coalesce(p_facts->'criteria', '[]'), 'award_scope', p_facts->'award_scope', 'criteria_extractor', p_facts->>'criteria_extractor')
   where scholarship_id = p_scholarship_id and read_status = 'read' and facts is not null;
  v := security.scholarship_criteria_apply_v1(p_scholarship_id);
  return jsonb_build_object('changes', to_jsonb(v));
end $function$
