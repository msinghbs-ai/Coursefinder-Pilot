CREATE OR REPLACE FUNCTION public.svc_ranking_import_validation_update(p_import_id uuid, p_status text, p_validation_summary jsonb, p_parse_summary jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'ranking'
AS $function$
begin
 if current_user not in ('service_role','postgres') then
   raise exception 'service role required' using errcode='42501';
 end if;
 if p_status not in ('uploaded','validated','parsed','reconciled','needs_review','applied','rejected') then
   raise exception 'invalid ranking import status' using errcode='22023';
 end if;
 update ranking.manual_imports
 set status=p_status,
     validation_summary=coalesce(p_validation_summary,'{}'::jsonb),
     parse_summary=coalesce(p_parse_summary,'{}'::jsonb),
     updated_at=now()
 where id=p_import_id;
 return found;
end
$function$
