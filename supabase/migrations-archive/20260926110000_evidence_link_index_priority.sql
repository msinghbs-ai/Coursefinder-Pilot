-- Package 7 (Decision 146): index captures from providers waiting on onboarding first
-- (providers with the most courses first, as in the onboarding queue), then everything else newest first.
create or replace function public.svc_evidence_link_index_next_v1(p_limit int default 60)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline','catalogue'
as $$
  with waiting as (
    select c.provider_id, count(*) n from catalogue.courses c
    where c.provider_id in (select distinct qi.provider_id from pipeline.layer2_scale_qualification_items qi
                            where qi.status in ('layer3_required','layer4_required','source_limited'))
    group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'path',x.storage_path,'mime',x.mime_type,'url',x.source_url,'type',x.evidence_type)),'[]'::jsonb)
  from (select e.id, e.storage_path, e.mime_type, e.source_url, e.evidence_type
        from pipeline.evidence_artifacts e
        left join pipeline.evidence_link_index_state st on st.evidence_id=e.id
        left join pipeline.sources s on s.id=e.source_id
        left join waiting w on w.provider_id=s.provider_id
        where e.storage_path is not null and e.storage_path !~ '^[a-z-]+://'
          and e.evidence_type in ('layer2_html_snapshot','layer2_extraction_input','source_snapshot','provider_contact_html_snapshot')
          and (e.mime_type ilike '%html%' or e.mime_type ilike '%json%')
          and (st.evidence_id is null or (st.status='error' and st.indexed_at < now()-interval '6 hours'))
        order by coalesce(w.n,0) desc, e.captured_at desc nulls last
        limit greatest(1,least(coalesce(p_limit,60),200))) x
$$;
revoke all on function public.svc_evidence_link_index_next_v1(int) from public, anon, authenticated;
grant execute on function public.svc_evidence_link_index_next_v1(int) to service_role;
