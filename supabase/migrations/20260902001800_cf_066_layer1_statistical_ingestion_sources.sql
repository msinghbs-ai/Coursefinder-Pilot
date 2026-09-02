begin;

update pipeline.sources
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
  'source_system','QILT',
  'dataset_class','statistics',
  'operational_surface','layer1_statistics',
  'identity_authority',false
), updated_at=now()
where country_id=(select id from ref.countries where iso_alpha2='AU')
  and (upper(coalesce(metadata->>'publisher',''))='QILT' or upper(label) like 'QILT%');

update pipeline.sources
set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
  'source_system','PRISMS',
  'dataset_class','statistics',
  'operational_surface','layer1_statistics',
  'identity_authority',false
), updated_at=now()
where country_id=(select id from ref.countries where iso_alpha2='AU')
  and (upper(coalesce(metadata->>'source_system',''))='PRISMS' or upper(label) like '%PRISMS%');

insert into pipeline.layer1_source_operations(
  source_id,authority_name,authority_domains,expected_format,expected_count_kind,
  active,paused,verification_cadence_days,ingestion_cadence_days,
  variance_warn_percent,variance_block_percent,previous_accepted_count,last_expected_count,
  last_source_hash,last_verified_at,verification_status,verification_message,variance_percent,variance_decision,
  next_verification_at,next_ingestion_at,change_reason,updated_at
)
select s.id,
  case when upper(s.metadata->>'source_system')='QILT'
       then 'Quality Indicators for Learning and Teaching (QILT)'
       else 'Australian Government Department of Education / PRISMS' end,
  case when upper(s.metadata->>'source_system')='QILT'
       then array['qilt.edu.au']::text[]
       else array['education.gov.au']::text[] end,
  case when upper(s.metadata->>'source_system')='QILT'
       then 'QILT published ZIP containing XLSX national report tables'
       else 'Department of Education published PRISMS XLSX workbook' end,
  'observations',
  true,false,
  case when upper(s.metadata->>'source_system')='QILT' then 30 else 7 end,
  case when upper(s.metadata->>'source_system')='QILT' then 90 else 30 end,
  5,20,
  case when upper(s.metadata->>'source_system')='QILT'
       then (select count(*)::bigint from catalogue.provider_outcomes po where po.source_id=s.id)
       else (select count(*)::bigint from catalogue.student_flow_observations fo where fo.source_id=s.id) end,
  case when upper(s.metadata->>'source_system')='QILT'
       then (select count(*)::bigint from catalogue.provider_outcomes po where po.source_id=s.id)
       else (select count(*)::bigint from catalogue.student_flow_observations fo where fo.source_id=s.id) end,
  (select e.content_hash from pipeline.evidence_artifacts e where e.source_id=s.id order by e.captured_at desc limit 1),
  coalesce(s.last_success_at,s.last_checked_at),
  case when coalesce(s.last_success_at,s.last_checked_at) is null then 'unverified' else 'passed' end,
  'Registered as a governed statistical ingestion source. Statistical observations do not define Provider/Course identity.',
  0,
  case when coalesce(s.last_success_at,s.last_checked_at) is null then 'unknown' else 'pass' end,
  now() + (case when upper(s.metadata->>'source_system')='QILT' then interval '30 days' else interval '7 days' end),
  now() + (case when upper(s.metadata->>'source_system')='QILT' then interval '90 days' else interval '30 days' end),
  'CF-CHG-20260902-066 Layer 1 statistical ingestion source registration',
  now()
from pipeline.sources s
where s.country_id=(select id from ref.countries where iso_alpha2='AU')
  and upper(coalesce(s.metadata->>'source_system','')) in ('QILT','PRISMS')
on conflict(source_id) do update set
  authority_name=excluded.authority_name,
  authority_domains=excluded.authority_domains,
  expected_format=excluded.expected_format,
  expected_count_kind='observations',
  active=true,
  verification_cadence_days=excluded.verification_cadence_days,
  ingestion_cadence_days=excluded.ingestion_cadence_days,
  change_reason=excluded.change_reason,
  updated_at=now();

insert into pipeline.layer1_source_operation_versions(source_id,version_no,snapshot,changed_by,change_reason)
select o.source_id,1,to_jsonb(o),null,'CF-CHG-20260902-066 initial statistical operations registration'
from pipeline.layer1_source_operations o
join pipeline.sources s on s.id=o.source_id
where upper(coalesce(s.metadata->>'source_system','')) in ('QILT','PRISMS')
  and not exists(select 1 from pipeline.layer1_source_operation_versions v where v.source_id=o.source_id);

commit;
