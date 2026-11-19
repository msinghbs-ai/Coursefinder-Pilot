create or replace function public.ui_provider_detail(p_provider_id uuid)
returns jsonb language sql stable security definer
set search_path='public','catalogue','pipeline','integration','ref','search','auth' as $$
select case when p.id is null then null else jsonb_build_object(
'id',p.id,'stable_key',p.stable_key,'canonical_name',p.canonical_name,'display_name',p.display_name,'country_code',c.iso_alpha2,'currency_code',c.default_currency_code,'city',p.primary_city,'website',p.website,'description',p.description,'lifecycle_status',p.lifecycle_status,'publication_status',p.publication_status,'last_verified_at',p.last_verified_at,
'identifiers',coalesce((select jsonb_agg(jsonb_build_object('scheme',i.scheme,'identifier',i.identifier,'authority',i.issuing_authority,'primary',i.is_primary,'valid_from',i.valid_from,'valid_to',i.valid_to,'source_id',i.source_id,'evidence_id',i.evidence_id,'verified_at',i.verified_at) order by i.is_primary desc,i.scheme) from catalogue.provider_identifiers i where i.provider_id=p.id),'[]'::jsonb),
'registrations',coalesce((select jsonb_agg(jsonb_build_object('scheme',r.registration_scheme,'code',r.registration_code,'classification',r.provider_classification,'status',r.status,'valid_from',r.valid_from,'valid_to',r.valid_to,'source_id',r.source_id,'evidence_id',r.evidence_id,'checked_at',r.checked_at) order by r.registration_scheme) from catalogue.provider_registrations r where r.provider_id=p.id),'[]'::jsonb),
'sources',coalesce((select jsonb_agg(distinct jsonb_build_object('id',s.id,'label',s.label,'type',s.source_type,'url',s.url,'status',s.status,'trust_rank',s.trust_rank)) from pipeline.sources s where s.provider_id=p.id or s.id=p.canonical_source_id),'[]'::jsonb),
'evidence',coalesce((with ids as (
 select e.id from pipeline.evidence_artifacts e where e.entity_id=p.id
 union select i.evidence_id from catalogue.provider_identifiers i where i.provider_id=p.id and i.evidence_id is not null
 union select r.evidence_id from catalogue.provider_registrations r where r.provider_id=p.id and r.evidence_id is not null
) select jsonb_agg(jsonb_build_object('id',e.id,'type',e.evidence_type,'source_url',e.source_url,'hash',e.content_hash,'captured_at',e.captured_at,'source_id',e.source_id) order by e.captured_at desc) from ids join pipeline.evidence_artifacts e using(id)),'[]'::jsonb),
'course_count',(select count(*) from catalogue.courses cc where cc.provider_id=p.id),
'projected_course_count',(select count(*) from search.course_documents d where d.provider_id=p.id),
'search_status',case when exists(select 1 from search.course_documents d where d.provider_id=p.id) then 'projected' else 'not_projected' end
) end from catalogue.providers p join ref.countries c on c.id=p.country_id where p.id=p_provider_id and auth.uid() is not null;
$$;
