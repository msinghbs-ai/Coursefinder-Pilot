CREATE OR REPLACE FUNCTION security.entry_level_map_v1(p_label text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select l.id from ref.study_levels l
   where l.code = case
     when p_label ~* 'phd|doctor' then 'doctorate'
     when p_label ~* 'master|postgrad' then 'masters'
     when p_label ~* 'graduate diploma' then 'graduate_diploma'
     when p_label ~* 'graduate certificate' then 'graduate_certificate'
     when p_label ~* 'associate degree' then 'associate_degree'
     when p_label ~* 'bachelor|degree|undergrad' then 'bachelor'
     when p_label ~* 'advanced diploma' then 'advanced_diploma'
     when p_label ~* 'diploma' then 'diploma'
     when p_label ~* 'foundation|pathway' then 'foundation'
     when p_label ~* 'certificate' then 'certificate'
   end
$function$
