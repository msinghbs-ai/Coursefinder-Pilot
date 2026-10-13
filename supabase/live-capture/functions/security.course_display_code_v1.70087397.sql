CREATE OR REPLACE FUNCTION security.course_display_code_v1(p_course uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case when ss.identifier is not null then jsonb_build_object('code', ss.identifier, 'kind', 'studysearch', 'label', 'StudySearch code')
              else jsonb_build_object('code', c.course_code, 'kind', 'own',
                     'label', coalesce((select s.label from catalogue.course_identifiers i join ref.course_code_schemes s on s.scheme = i.scheme
                                         where i.course_id = c.id and i.identifier = c.course_code limit 1), 'Course code')) end
    from catalogue.courses c
    left join lateral (select i.identifier from catalogue.course_identifiers i where i.course_id = c.id and i.scheme = 'studysearch' limit 1) ss on true
   where c.id = p_course
$function$
