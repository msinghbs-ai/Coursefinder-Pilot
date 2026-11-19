insert into integration.systems(code,name,system_type,base_url,status,config) values
 ('ca_ns_nscc_programs','Nova Scotia Community College programme catalogue','institutional_catalogue','https://www.nscc.ca','active','{"country":"CA","jurisdiction":"NS","identity":"program_code"}'::jsonb),
 ('ca_sk_saskpoly_programs','Saskatchewan Polytechnic programme XML catalogue','institutional_catalogue','https://saskpolytech.ca','active','{"country":"CA","jurisdiction":"SK","identity":"program_code_xml"}'::jsonb)
on conflict(code) do update set name=excluded.name,system_type=excluded.system_type,base_url=excluded.base_url,status='active',config=excluded.config,updated_at=now();

with ca as (select id country_id from ref.countries where iso_alpha2='CA'), defs as (
 select * from (values
  ('ca_ns_nscc_programs','O19091820452','https://www.nscc.ca/programs-and-courses/programs/programlisting.aspx?list=alpha','Nova Scotia Community College programmes','nscc_program_code','NS'),
  ('ca_sk_saskpoly_programs','O19425521849','https://saskpolytech.ca/sitemap.xml','Saskatchewan Polytechnic programmes','saskpoly_program_code','SK')
 ) v(system_code,dli,url,label,scheme,jurisdiction)
), resolved as (
 select i.id system_id,pi.provider_id,d.*,ca.country_id
 from defs d join integration.systems i on i.code=d.system_code cross join ca
 join catalogue.provider_identifiers pi on pi.country_id=ca.country_id and pi.scheme='ircc_dli' and pi.identifier=d.dli and pi.is_primary
)
insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'institutional_catalogue',r.system_id,r.provider_id,r.country_id,r.url,r.label,95,'active',jsonb_build_object('layer','1','country','CA','province',r.jurisdiction,'provider_dli',r.dli,'coverage_role','first_party_course_identity_current_catalogue','course_identity_scheme',r.scheme,'title_identity_allowed',false)
from resolved r where not exists(select 1 from pipeline.sources s where s.system_id=r.system_id and s.provider_id=r.provider_id);

insert into pipeline.ca_source_qualifications(source_id,jurisdiction_code,authority_role,course_identity_scheme,stable_program_id_proof,provider_dli_mapping_status,runtime_fetch_status,coverage_scope,notes,updated_at)
select s.id,case i.code when 'ca_ns_nscc_programs' then 'NS' else 'SK' end,'authoritative first-party institutional catalogue',case i.code when 'ca_ns_nscc_programs' then 'nscc_program_code' else 'saskpoly_program_code' end,case i.code when 'ca_ns_nscc_programs' then 'first-party programme detail meta program_code independent of URL/title' else 'first-party structured programme XML <code> with explicit active lifecycle' end,'verified_static_dli','pass',case i.code when 'ca_ns_nscc_programs' then 'current NSCC A-Z programme catalogue' else 'current non-archive Saskatchewan Polytechnic programme XML inventory from sitemap' end,'No title/name identity. Provider pinned by verified IRCC DLI.',now()
from pipeline.sources s join integration.systems i on i.id=s.system_id where i.code in ('ca_ns_nscc_programs','ca_sk_saskpoly_programs')
on conflict(source_id) do update set jurisdiction_code=excluded.jurisdiction_code,authority_role=excluded.authority_role,course_identity_scheme=excluded.course_identity_scheme,stable_program_id_proof=excluded.stable_program_id_proof,provider_dli_mapping_status=excluded.provider_dli_mapping_status,runtime_fetch_status=excluded.runtime_fetch_status,coverage_scope=excluded.coverage_scope,notes=excluded.notes,updated_at=now();
