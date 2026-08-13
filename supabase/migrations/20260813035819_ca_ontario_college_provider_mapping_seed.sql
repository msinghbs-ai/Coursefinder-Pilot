with mapping(code,dli,expected_name) as (values
 ('ALGO','O19358971022','Algonquin College'),
 ('BORE','O19395678039','Collège Boréal'),
 ('CAMB','O19394699409','Cambrian College of Applied Arts and Technology'),
 ('CANA','O19395535239','Canadore College'),
 ('CENT','O19394700003','Centennial College'),
 ('CONF','O19376986752','Confederation College'),
 ('CONS','O19376158572','Conestoga College'),
 ('DURH','O19361081012','Durham College'),
 ('FANS','O19361039982','Fanshawe College'),
 ('GEOR','O19395677361','Georgian College'),
 ('GRBR','O19283850612','George Brown College'),
 ('HUMB','O19376943122','Humber College'),
 ('LACI','O19395422135','La Cité collégiale'),
 ('LAMB','O19305293332','Lambton College'),
 ('LOYT','O19359011572','Loyalist College'),
 ('MOHA','O19376045902','Mohawk College'),
 ('NIAG','O19396019469','Niagara College Canada'),
 ('NORT','O19315830082','Northern College'),
 ('SAUL','O19395677683','Sault College'),
 ('SENE','O19395536013','Seneca College'),
 ('SHER','O19385946782','Sheridan College'),
 ('SLAW','O19332845222','St. Lawrence College'),
 ('SSFL','O19303189722','Fleming College'),
 ('STCL','O19395083703','St. Clair College')
), resolved as (
 select m.*,s.id source_id,pi.provider_id
 from mapping m
 join integration.systems i on i.code='ca_on_public_college_programs'
 join pipeline.sources s on s.system_id=i.id and s.provider_id is null
 join ref.countries c on c.id=s.country_id and upper(c.iso_alpha2::text)='CA'
 join catalogue.provider_identifiers pi on pi.country_id=c.id and lower(pi.scheme)='ircc_dli' and upper(pi.identifier)=upper(m.dli)
)
insert into pipeline.source_provider_mappings(source_id,source_entity_key,source_entity_name,provider_id,match_method,match_confidence,status,verified_at,metadata)
select source_id,'on-college:'||lower(code),code,provider_id,'official_ontario_college_code_to_verified_ircc_dli',1.0000,'verified',now(),
 jsonb_build_object('ircc_dli',dli,'expected_name',expected_name,'verified_scope','Ontario public college ministry code -> canonical IRCC DLI Provider','ontario_college_code',code,'identity_write_allowed',false)
from resolved
on conflict (source_id,source_entity_key) do update set
 source_entity_name=excluded.source_entity_name,provider_id=excluded.provider_id,match_method=excluded.match_method,match_confidence=excluded.match_confidence,status='verified',verified_at=now(),metadata=excluded.metadata,updated_at=now();