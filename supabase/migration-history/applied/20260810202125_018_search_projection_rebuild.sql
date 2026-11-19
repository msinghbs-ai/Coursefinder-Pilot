create or replace function search.rebuild_course_documents()
returns bigint
language plpgsql
security definer
set search_path=search,catalogue,scholarship,publishing,ref,extensions
as $$
declare v_generation bigint; v_count bigint;
begin
  update search.projection_state set generation=generation+1,rebuilt_at=now() where projection_code='courses' returning generation into v_generation;
  delete from search.course_documents;
  insert into search.course_documents(
    course_id,provider_id,country_id,study_level_id,primary_field_id,provider_name,course_title,collection_names,academic_option_names,description,search_text,search_tsv,
    has_fee,has_intake,has_english,has_scholarship,publication_status,completeness_score,catalogue_generation,content_hash,updated_at)
  select c.id,c.provider_id,p.country_id,c.study_level_id,c.primary_field_id,coalesce(p.display_name,p.canonical_name),c.canonical_title,
    coalesce((select array_agg(distinct cc.name order by cc.name) from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),'{}'::text[]),
    coalesce((select array_agg(distinct ao.name order by ao.name) from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),'{}'::text[]),
    c.description,
    concat_ws(' ',coalesce(p.display_name,p.canonical_name),c.canonical_title,coalesce(c.description,''),coalesce((select string_agg(distinct cc.name,' ') from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),''),coalesce((select string_agg(distinct ao.name,' ') from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),'')),
    to_tsvector('english',concat_ws(' ',coalesce(p.display_name,p.canonical_name),c.canonical_title,coalesce(c.description,''),coalesce((select string_agg(distinct cc.name,' ') from catalogue.course_collection_memberships m join catalogue.course_collections cc on cc.id=m.collection_id where m.course_id=c.id),''),coalesce((select string_agg(distinct ao.name,' ') from catalogue.course_academic_options ao where ao.course_id=c.id and ao.status='active'),''))),
    exists(select 1 from catalogue.course_fees f where f.course_id=c.id),
    exists(select 1 from catalogue.course_intakes i where i.course_id=c.id and i.status='active'),
    exists(select 1 from catalogue.course_english_requirements e where e.course_id=c.id),
    exists(select 1 from scholarship.scopes ss join scholarship.scholarships s on s.id=ss.scholarship_id where s.publication_status in ('published','internal') and ((ss.scope_type='course' and ss.course_id=c.id) or (ss.scope_type='provider' and ss.provider_id=c.provider_id))),
    c.publication_status,
    (select max(es.completeness_score) from publishing.entity_states es where es.entity_id=c.id),
    v_generation,
    encode(extensions.digest(concat_ws('|',c.id::text,c.updated_at::text,coalesce(c.description,'')),'sha256'),'hex'),now()
  from catalogue.courses c join catalogue.providers p on p.id=c.provider_id
  where c.lifecycle_status='active';
  get diagnostics v_count=row_count;
  update search.projection_state set row_count=v_count,rebuilt_at=now() where projection_code='courses';
  return v_count;
end$$;
revoke all on function search.rebuild_course_documents() from public,anon,authenticated;
grant execute on function search.rebuild_course_documents() to service_role;
