CREATE OR REPLACE FUNCTION public.ui_scholarships_list(p_limit integer DEFAULT 500)
 RETURNS TABLE(id uuid, stable_key text, name text, provider_id uuid, provider_name text, scholarship_type text, audience text, award_value_text text, academic_year integer, publication_status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'scholarship', 'catalogue', 'auth'
AS $function$
select s.id,s.stable_key,s.name,s.provider_id,coalesce(p.display_name,p.canonical_name),s.scholarship_type,s.audience,s.award_value_text,s.academic_year,s.publication_status
from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id
where auth.uid() is not null order by coalesce(p.display_name,p.canonical_name),s.name limit least(greatest(coalesce(p_limit,500),1),1000)
$function$
