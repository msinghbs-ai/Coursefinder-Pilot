do $d$
declare v text; n text;
begin
  v := pg_get_functiondef('api.website_v2_scholarship_item(uuid)'::regprocedure);
  n := replace(v, $o$areas as (select array_agg(distinct f.code) codes from scholarship.scopes sc join s on sc.scholarship_id=s.id join ref.fields_of_study f on f.id=sc.field_id where sc.include_exclude is distinct from 'exclude')$o$,
                  $o$areas as (select array_agg(distinct d.primary_field_code order by d.primary_field_code) codes from scholarship.course_mappings m join s on m.scholarship_id=s.id join search.course_documents d on d.course_id=m.course_id where m.mapping_state='mapped' and d.primary_field_code is not null)$o$);
  if n = v then raise exception 'item anchor not found'; end if;
  execute n;
  v := pg_get_functiondef('public.website_v2_scholarships(jsonb,integer,integer)'::regprocedure);
  n := replace(v, $o$(v_areas is null or exists (select 1 from scholarship.scopes sc join ref.fields_of_study fo on fo.id=sc.field_id where sc.scholarship_id=s.id and fo.code = any(v_areas)))$o$,
                  $o$(v_areas is null or exists (select 1 from scholarship.course_mappings m join search.course_documents d on d.course_id=m.course_id where m.scholarship_id=s.id and m.mapping_state='mapped' and d.primary_field_code = any(v_areas)))$o$);
  if n = v then raise exception 'list anchor not found'; end if;
  execute n;
end $d$
