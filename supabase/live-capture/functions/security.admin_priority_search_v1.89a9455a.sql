CREATE OR REPLACE FUNCTION security.admin_priority_search_v1(p_kind text, p_q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'catalogue', 'ref', 'security'
AS $function$
declare q text:='%'||btrim(coalesce(p_q,''))||'%';
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  if length(btrim(coalesce(p_q,'')))<2 then return '[]'::jsonb; end if;
  if p_kind='provider' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',pr.id,'label',coalesce(pr.display_name,pr.canonical_name),'detail',concat_ws(' · ',s.name,k.name)) x
      from catalogue.providers pr left join ref.subdivisions s on s.id=pr.subdivision_id left join ref.countries k on k.id=pr.country_id
     where pr.display_name ilike q or pr.canonical_name ilike q or pr.short_name ilike q order by (select count(*) from catalogue.courses c where c.provider_id=pr.id and c.lifecycle_status='active') desc, length(coalesce(pr.display_name,pr.canonical_name)) limit 20) y);
  elsif p_kind='course' then
    return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select jsonb_build_object('id',c.id,'label',coalesce(c.display_title,c.canonical_title),'detail',concat_ws(' · ',c.course_code,coalesce(pr.display_name,pr.canonical_name))) x
      from catalogue.courses c left join catalogue.providers pr on pr.id=c.provider_id
     where c.lifecycle_status='active' and (c.course_code ilike q or c.canonical_title ilike q or c.display_title ilike q) limit 20) y);
  end if;
  raise exception 'search by provider or course';
end $function$
