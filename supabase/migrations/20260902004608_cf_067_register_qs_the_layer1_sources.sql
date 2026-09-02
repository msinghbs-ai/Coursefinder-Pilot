insert into pipeline.sources(source_type,url,label,trust_rank,status,metadata)
select * from (values
('structured_rankings','https://www.topuniversities.com/world-university-rankings/2026','QS World University Rankings 2026',85,'active',jsonb_build_object('layer','1','scope','global','publisher','QS Quacquarelli Symonds','edition_year',2026,'dataset_class','rankings','source_system','QS','acquisition_mode','publisher_page_or_manual_file','identity_authority',false,'operational_surface','layer1_statistics','ranking_system_code','qs_wur')),
('structured_rankings','https://www.topuniversities.com/world-university-rankings/2027','QS World University Rankings 2027',85,'active',jsonb_build_object('layer','1','scope','global','publisher','QS Quacquarelli Symonds','edition_year',2027,'dataset_class','rankings','source_system','QS','acquisition_mode','publisher_page_or_manual_file','identity_authority',false,'operational_surface','layer1_statistics','ranking_system_code','qs_wur')),
('structured_rankings','https://www.timeshighereducation.com/world-university-rankings/latest/world-ranking','Times Higher Education World University Rankings 2026',85,'active',jsonb_build_object('layer','1','scope','global','publisher','Times Higher Education','edition_year',2026,'dataset_class','rankings','source_system','THE','acquisition_mode','publisher_page_or_manual_file','identity_authority',false,'operational_surface','layer1_statistics','ranking_system_code','the_wur'))
) v(source_type,url,label,trust_rank,status,metadata)
where not exists(select 1 from pipeline.sources s where s.label=v.label);

insert into pipeline.layer1_source_operations(
 source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,
 verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,change_reason
)
select s.id,
 case when s.metadata->>'source_system'='QS' then 'QS Quacquarelli Symonds' else 'Times Higher Education' end,
 case when s.metadata->>'source_system'='QS' then array['topuniversities.com']::text[] else array['timeshighereducation.com']::text[] end,
 case when s.metadata->>'source_system'='QS' then 'QS publisher page or authorised CSV/XLSX publisher artifact' else 'THE publisher page or authorised CSV/XLSX publisher artifact' end,
 'ranking observations',true,false,30,365,10,35,
 'CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
from pipeline.sources s
where coalesce(s.metadata->>'ranking_system_code','') in ('qs_wur','the_wur')
on conflict(source_id) do update set
 authority_name=excluded.authority_name,authority_domains=excluded.authority_domains,expected_format=excluded.expected_format,
 expected_count_kind=excluded.expected_count_kind,active=true,change_reason=excluded.change_reason,updated_at=now();

insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,change_reason)
select o.source_id,
 coalesce((select max(v.version_no)+1 from pipeline.layer1_source_operation_versions v where v.source_id=o.source_id),1),
 to_jsonb(o),'CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
from pipeline.layer1_source_operations o
join pipeline.sources s on s.id=o.source_id
where coalesce(s.metadata->>'ranking_system_code','') in ('qs_wur','the_wur')
and not exists(
 select 1 from pipeline.layer1_source_operation_versions v
 where v.source_id=o.source_id and v.change_reason='CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
);