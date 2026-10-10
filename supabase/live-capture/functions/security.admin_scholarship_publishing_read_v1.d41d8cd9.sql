CREATE OR REPLACE FUNCTION security.admin_scholarship_publishing_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'scholarship', 'catalogue', 'security'
AS $function$
begin
  if auth.uid() is null or security.current_role_rank()<3 then raise exception 'assigned CourseFinder role required' using errcode='42501'; end if;
  return (with p as (select * from security.scholarship_publishability_v1())
  select jsonb_build_object('can_control',security.current_role_rank()>=5,
    'counts',jsonb_build_object('published',(select count(*) from scholarship.scholarships where publication_status='published'),
       'eligible',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
         and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id)),
       'held',(select count(*) from pipeline.scholarship_publication_holds where released_at is null),
       'domestic_only',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),
       'active',(select count(*) from scholarship.scholarships where lifecycle_status='active'),
       'published_failing',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.publication_status='published' and not p.publishable)),
    'published_failing',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,'reason',array_to_string(p.missing,'; ')) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published' and not p.publishable),
    'not_publishable_reasons',(select jsonb_object_agg(m,n) from (select unnest(p.missing) m,count(*) n from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' group by 1) x),
    'eligible',(select coalesce(jsonb_agg(x order by x->>'provider',x->>'name'),'[]'::jsonb) from (select jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),
         'value',scholarship.value_label(s.id),
         'page',s.source_url,'courses',(select count(*) from scholarship.course_mappings m where m.scholarship_id=s.id and m.mapping_state='mapped')) x
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where p.publishable and coalesce(s.publication_status,'unpublished')<>'published'
        and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id=s.id) limit 300) y),
    'domestic_only',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,
         'published',s.publication_status='published',
         'words',(select left(cr.human_text,240) from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type' and cr.value_json->>'by'='scholarship_sweep' limit 1))
         order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),
    'held',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'reason',h.reason,'at',h.held_at) order by h.held_at desc),'[]'::jsonb)
       from pipeline.scholarship_publication_holds h join scholarship.scholarships s on s.id=h.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id where h.released_at is null),
    'published',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url) order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from scholarship.scholarships s left join catalogue.providers pr on pr.id=s.provider_id where s.publication_status='published'),
    'events',(select coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'action',e.action,'target',e.target,'detail',e.detail) order by e.created_at desc),'[]'::jsonb)
                from (select * from pipeline.admin_control_events where area='scholarships' order by created_at desc limit 10) e)));
end $function$
