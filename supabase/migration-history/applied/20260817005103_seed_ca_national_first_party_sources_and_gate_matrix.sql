create table if not exists pipeline.ca_source_qualifications (
  source_id uuid primary key references pipeline.sources(id) on delete cascade,
  jurisdiction_code text not null,
  authority_role text not null,
  provider_identity_scheme text not null default 'ircc_dli',
  course_identity_scheme text,
  stable_program_id_proof text,
  provider_dli_mapping_status text not null default 'pending',
  runtime_fetch_status text not null default 'pending',
  evidence_status text not null default 'pending',
  dry_run_status text not null default 'pending',
  apply_status text not null default 'pending',
  idempotency_status text not null default 'pending',
  integrity_status text not null default 'pending',
  performance_status text not null default 'pending',
  coverage_scope text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  verified_at timestamptz,
  updated_at timestamptz not null default now()
);
revoke all on pipeline.ca_source_qualifications from public,anon,authenticated;
grant select,insert,update,delete on pipeline.ca_source_qualifications to service_role;

insert into integration.systems(code,name,system_type,base_url,status,config) values
 ('ca_nt_aurora_programs','Aurora College programme catalogue','institutional_catalogue','https://www.auroracollege.nt.ca','active','{"country":"CA","jurisdiction":"NT","identity":"wordpress_post_id"}'::jsonb),
 ('ca_yt_yukon_programs','Yukon University programme catalogue','institutional_catalogue','https://www.yukonu.ca','active','{"country":"CA","jurisdiction":"YT","identity":"drupal_node_id"}'::jsonb),
 ('ca_nl_cna_programs','College of the North Atlantic programme catalogue','institutional_catalogue','https://www.cna.nl.ca','active','{"country":"CA","jurisdiction":"NL","identity":"published_courseCode"}'::jsonb)
on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now();

with ca as (select id country_id from ref.countries where iso_alpha2='CA'), defs as (
 select * from (values
  ('ca_nt_aurora_programs','O19348462392','https://www.auroracollege.nt.ca/programs/','Aurora College academic programmes','aurora_wp_post_id','NT'),
  ('ca_yt_yukon_programs','O19604209351','https://www.yukonu.ca/programs/all','Yukon University programmes','yukonu_drupal_node_id','YT'),
  ('ca_nl_cna_programs','O19441088976','https://www.cna.nl.ca/programs-courses/program-guide.aspx','College of the North Atlantic programme guide','cna_course_code','NL')
 ) v(system_code,dli,url,label,scheme,jurisdiction)
), resolved as (
 select i.id system_id,pi.provider_id,d.*,ca.country_id
 from defs d join integration.systems i on i.code=d.system_code cross join ca
 join catalogue.provider_identifiers pi on pi.country_id=ca.country_id and pi.scheme='ircc_dli' and pi.identifier=d.dli and pi.is_primary
)
insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'institutional_catalogue',r.system_id,r.provider_id,r.country_id,r.url,r.label,95,'active',
 jsonb_build_object('layer','1','country','CA','province',r.jurisdiction,'provider_dli',r.dli,'coverage_role','first_party_course_identity_current_catalogue','course_identity_scheme',r.scheme,'title_identity_allowed',false,'runtime_edge_pending',true)
from resolved r
where not exists(select 1 from pipeline.sources s where s.system_id=r.system_id and s.provider_id=r.provider_id);

insert into pipeline.ca_source_qualifications(source_id,jurisdiction_code,authority_role,course_identity_scheme,stable_program_id_proof,provider_dli_mapping_status,runtime_fetch_status,coverage_scope,notes,updated_at)
select s.id,
 case i.code when 'ca_nt_aurora_programs' then 'NT' when 'ca_yt_yukon_programs' then 'YT' when 'ca_nl_cna_programs' then 'NL' end,
 'authoritative first-party institutional catalogue',
 case i.code when 'ca_nt_aurora_programs' then 'aurora_wp_post_id' when 'ca_yt_yukon_programs' then 'yukonu_drupal_node_id' when 'ca_nl_cna_programs' then 'cna_course_code' end,
 case i.code when 'ca_nt_aurora_programs' then 'WordPress immutable numeric post ID exposed in first-party program page body class' when 'ca_yt_yukon_programs' then 'Drupal numeric node ID exposed in first-party program page body class' when 'ca_nl_cna_programs' then 'first-party JSON-LD Course.courseCode on programme guide' end,
 'verified_static_dli','pass',
 case i.code when 'ca_nt_aurora_programs' then 'current Aurora College academic programmes; current NT DLI jurisdiction' when 'ca_yt_yukon_programs' then 'current Yukon University programmes; primary public YT DLI' else 'current CNA programme guide; major public NL provider' end,
 'No title/name identity. Provider pinned by verified IRCC DLI.',now()
from pipeline.sources s join integration.systems i on i.id=s.system_id
where i.code in ('ca_nt_aurora_programs','ca_yt_yukon_programs','ca_nl_cna_programs')
on conflict(source_id) do update set jurisdiction_code=excluded.jurisdiction_code,authority_role=excluded.authority_role,course_identity_scheme=excluded.course_identity_scheme,stable_program_id_proof=excluded.stable_program_id_proof,provider_dli_mapping_status=excluded.provider_dli_mapping_status,runtime_fetch_status=excluded.runtime_fetch_status,coverage_scope=excluded.coverage_scope,notes=excluded.notes,updated_at=now();
