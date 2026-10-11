CREATE OR REPLACE FUNCTION security.scholarship_from_record_register(p_scholarship_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from scholarship.scholarships s join scholarship.registers r on r.source_id = s.source_id and r.role = 'record'
                  where s.id = p_scholarship_id)
$function$
