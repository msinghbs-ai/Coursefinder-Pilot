create or replace function public.ui_provider_detail(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path='public','catalogue','pipeline','integration','ref','search','auth' as $$
select case when p.id is null then null else jsonb_build_object(
'id',p.id,'stable_key',p.stable_key,'canonical_name',p.canonical_name,'display_name',p.display_name,'country_code',c.iso_alpha2,'city',p.primary_city,'website',p.website,'description',p.description,'lifecycle_status',p.lifecycle_status,'publication_status',p.publication_status,'last_verified_at',p.last_verified_at,
'identifiers',coalesce((select jsonb_agg(jsonb_build_object('scheme',i.scheme,'identifier',i.identifier,'authority',i.issuing_authority,'primary',i.is_primary,'valid_from',i.valid_from,'valid_to',i.valid_to,'source_id',i.source_id,'evidence_id',i.evidence_id,'verified_at',i.verified_at) order by i.is_primary desc,i.scheme) from catalogue.provider_identifiers i where i.provider_id=p.id),'[]'::jsonb),
'registrations',coalesce((select jsonb_agg(jsonb_build_object('scheme',r.registration_scheme,'code',r.registration_code,'classification',r.provider_classification,'status',r.status,'valid_from',r.valid_from,'valid_to',r.valid_to,'source_id',r.source_id,'evidence_id',r.evidence_id,'checked_at',r.checked_at) order by r.registration_scheme) from catalogue.provider_registrations r where r.provider_id=p.id),'[]'::jsonb),
'sources',coalesce((select jsonb_agg(distinct jsonb_build_object('id',s.id,'label',s.label,'type',s.source_type,'url',s.url,'status',s.status,'trust_rank',s.trust_rank)) from pipeline.sources s where s.provider_id=p.id or s.id=p.canonical_source_id),'[]'::jsonb),
'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'hash',e.content_hash,'captured_at',e.captured_at,'source_id',e.source_id) order by e.captured_at desc) from pipeline.evidence_artifacts e where e.entity_id=p.id),'[]'::jsonb),
'course_count',(select count(*) from catalogue.courses cc where cc.provider_id=p.id),
'projected_course_count',(select count(*) from search.course_documents d where d.provider_id=p.id),
'search_status',case when exists(select 1 from search.course_documents d where d.provider_id=p.id) then 'projected' else 'not_projected' end
) end from catalogue.providers p join ref.countries c on c.id=p.country_id where p.id=p_provider_id and auth.uid() is not null;
$$;

create or replace function public.ui_attribute_families_list()
returns table(id uuid,code text,name text,entity_type text,description text,is_default boolean,status text,group_count bigint,attribute_count bigint)
language sql stable security definer set search_path='public','pim','auth' as $$
select f.id,f.code,f.name,f.entity_type,f.description,f.is_default,f.status,count(distinct fg.group_id),count(distinct fa.attribute_id) from pim.attribute_families f left join pim.family_groups fg on fg.family_id=f.id left join pim.family_attributes fa on fa.family_id=f.id where auth.uid() is not null group by f.id order by f.entity_type,f.name;
$$;

create or replace function public.ui_attribute_groups_list()
returns table(id uuid,code text,name text,entity_type text,description text,display_order integer,status text,attribute_count bigint,family_count bigint)
language sql stable security definer set search_path='public','pim','auth' as $$
select g.id,g.code,g.name,g.entity_type,g.description,g.display_order,g.status,count(distinct a.id),count(distinct fg.family_id) from pim.attribute_groups g left join pim.attribute_definitions a on a.group_id=g.id left join pim.family_groups fg on fg.group_id=g.id where auth.uid() is not null group by g.id order by g.entity_type,g.display_order,g.name;
$$;

create or replace function public.ui_attribute_options_list(p_limit integer default 2000)
returns table(id uuid,attribute_id uuid,attribute_code text,attribute_name text,code text,label text,locale text,display_order integer,status text)
language sql stable security definer set search_path='public','pim','auth' as $$
select o.id,o.attribute_id,a.code,a.name,o.code,o.label,o.locale,o.display_order,o.status from pim.attribute_options o join pim.attribute_definitions a on a.id=o.attribute_id where auth.uid() is not null order by a.name,o.display_order,o.label limit least(greatest(coalesce(p_limit,2000),1),5000);
$$;

create or replace function public.ui_completeness_profiles_list()
returns table(id uuid,code text,name text,entity_type text,family_name text,country_code character,channel_code text,minimum_publish_score numeric,status text,requirement_count bigint,mandatory_count bigint)
language sql stable security definer set search_path='public','pim','ref','auth' as $$
select cp.id,cp.code,cp.name,cp.entity_type,af.name,c.iso_alpha2,cp.channel_code,cp.minimum_publish_score,cp.status,count(cr.id),count(cr.id) filter(where cr.is_mandatory) from pim.completeness_profiles cp left join pim.attribute_families af on af.id=cp.family_id left join ref.countries c on c.id=cp.country_id left join pim.completeness_requirements cr on cr.profile_id=cp.id where auth.uid() is not null group by cp.id,af.name,c.iso_alpha2 order by cp.entity_type,cp.name;
$$;

create or replace function public.ui_evidence_governance_list(p_limit integer default 1000)
returns table(id uuid,entity_id uuid,evidence_type text,source_label text,source_type text,source_url text,storage_path text,content_hash text,mime_type text,captured_at timestamptz,valid_from timestamptz,valid_to timestamptz,supersedes_evidence_id uuid,metadata jsonb)
language sql stable security definer set search_path='public','pipeline','auth' as $$
select e.id,e.entity_id,e.evidence_type,s.label,s.source_type,e.source_url,e.storage_path,e.content_hash,e.mime_type,e.captured_at,e.valid_from,e.valid_to,e.supersedes_evidence_id,e.metadata from pipeline.evidence_artifacts e left join pipeline.sources s on s.id=e.source_id where auth.uid() is not null order by e.captured_at desc limit least(greatest(coalesce(p_limit,1000),1),5000);
$$;

create or replace function public.ui_scholarship_detail(p_scholarship_id uuid)
returns jsonb language sql stable security definer set search_path='public','scholarship','catalogue','pipeline','auth' as $$
select case when s.id is null then null else jsonb_build_object(
'id',s.id,'stable_key',s.stable_key,'name',s.name,'provider_id',s.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'type',s.scholarship_type,'audience',s.audience,'description',s.description,'award_value_text',s.award_value_text,'lifecycle_status',s.lifecycle_status,'publication_status',s.publication_status,'confidence',s.confidence,'source_url',s.source_url,'source_id',s.source_id,'evidence_id',s.evidence_id,
'identifiers',coalesce((select jsonb_agg(to_jsonb(i) order by i.is_primary desc,i.scheme) from scholarship.identifiers i where i.scholarship_id=s.id),'[]'::jsonb),
'cycles',coalesce((select jsonb_agg(to_jsonb(cy) order by cy.academic_year desc nulls last,cy.cycle_code) from scholarship.offering_cycles cy where cy.scholarship_id=s.id),'[]'::jsonb),
'windows',coalesce((select jsonb_agg(to_jsonb(w) order by w.opens_at nulls last,w.label) from scholarship.application_windows w where w.scholarship_id=s.id),'[]'::jsonb),
'scopes',coalesce((select jsonb_agg(to_jsonb(sc) order by sc.scope_type) from scholarship.scopes sc where sc.scholarship_id=s.id),'[]'::jsonb),
'criterion_groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.display_order,g.group_code) from scholarship.criterion_groups g where g.scholarship_id=s.id),'[]'::jsonb),
'criteria',coalesce((select jsonb_agg(to_jsonb(cr) order by cr.criterion_type) from scholarship.criteria cr where cr.scholarship_id=s.id),'[]'::jsonb),
'award_tiers',coalesce((select jsonb_agg(to_jsonb(a) order by a.display_order,a.label) from scholarship.award_tiers a where a.scholarship_id=s.id),'[]'::jsonb),
'coverage',coalesce((select jsonb_agg(to_jsonb(cv) order by cv.coverage_type) from scholarship.coverage cv where cv.scholarship_id=s.id),'[]'::jsonb),
'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'hash',e.content_hash,'captured_at',e.captured_at) order by e.captured_at desc) from pipeline.evidence_artifacts e where e.id=s.evidence_id or e.entity_id=s.id),'[]'::jsonb)
) end from scholarship.scholarships s left join catalogue.providers p on p.id=s.provider_id where s.id=p_scholarship_id and auth.uid() is not null;
$$;

revoke execute on function public.ui_provider_detail(uuid) from public,anon;
revoke execute on function public.ui_attribute_families_list() from public,anon;
revoke execute on function public.ui_attribute_groups_list() from public,anon;
revoke execute on function public.ui_attribute_options_list(integer) from public,anon;
revoke execute on function public.ui_completeness_profiles_list() from public,anon;
revoke execute on function public.ui_evidence_governance_list(integer) from public,anon;
revoke execute on function public.ui_scholarship_detail(uuid) from public,anon;
grant execute on function public.ui_provider_detail(uuid) to authenticated;
grant execute on function public.ui_attribute_families_list() to authenticated;
grant execute on function public.ui_attribute_groups_list() to authenticated;
grant execute on function public.ui_attribute_options_list(integer) to authenticated;
grant execute on function public.ui_completeness_profiles_list() to authenticated;
grant execute on function public.ui_evidence_governance_list(integer) to authenticated;
grant execute on function public.ui_scholarship_detail(uuid) to authenticated;
