
insert into pipeline.layer1_source_operations(
  source_id,authority_name,authority_domains,expected_format,expected_count_kind,
  active,paused,verification_cadence_days,ingestion_cadence_days,
  variance_warn_percent,variance_block_percent,change_reason
)
select s.id,
  case when s.metadata->>'source_system'='QS' then 'QS Quacquarelli Symonds' else 'Times Higher Education' end,
  case when s.metadata->>'source_system'='QS' then array['topuniversities.com']::text[] else array['timeshighereducation.com']::text[] end,
  case when s.metadata->>'source_system'='QS' then 'QS publisher page or authorised CSV/XLSX publisher artifact' else 'THE publisher page or authorised CSV/XLSX publisher artifact' end,
  'ranking observations',
  true,false,30,365,10,35,
  'CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
from pipeline.sources s
where coalesce(s.metadata->>'ranking_system_code','') in ('qs_wur','the_wur')
on conflict(source_id) do update set
  authority_name=excluded.authority_name,
  authority_domains=excluded.authority_domains,
  expected_format=excluded.expected_format,
  expected_count_kind=excluded.expected_count_kind,
  active=true,
  change_reason=excluded.change_reason,
  updated_at=now();

insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,change_reason)
select o.source_id,
  coalesce((select max(v.version_no)+1 from pipeline.layer1_source_operation_versions v where v.source_id=o.source_id),1),
  to_jsonb(o),
  'CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
from pipeline.layer1_source_operations o
join pipeline.sources s on s.id=o.source_id
where coalesce(s.metadata->>'ranking_system_code','') in ('qs_wur','the_wur')
and not exists(
  select 1 from pipeline.layer1_source_operation_versions v
  where v.source_id=o.source_id
    and v.change_reason='CF-CHG-20260902-067 QS/THE Layer 1 ranking ingestion registration'
);
