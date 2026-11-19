-- CF-247 Decision 162 step 2: fee-schedule sources for Charles Darwin University (00300K) and Swinburne (00111D).
-- Same pattern as Federation and Western Sydney: one source per provider, qualified for international fees only,
-- bound by the exact CRICOS code inside the provider. Apply only after a clean dry run.
insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'provider_fee_schedule', t.system_id, (select pr.provider_id from catalogue.provider_registrations pr where upper(pr.registration_code)=x.cricos and lower(pr.registration_scheme)='cricos' limit 1),
       t.country_id, x.url, x.label, 95, 'active',
       jsonb_build_object('facts',jsonb_build_array('international_fee'),'provider_cricos',x.cricos,'course_identity','exact CRICOS course code within the provider','decision','Decision 162')
  from (values ('00300K','https://www.cdu.edu.au/study/fees','Charles Darwin University international tuition fee schedule'),
               ('00111D','https://www.swinburne.edu.au/study/international/fees/','Swinburne University of Technology international course fee schedules')) x(cricos,url,label)
  cross join lateral (select s0.system_id, s0.country_id from pipeline.sources s0 where s0.source_type='provider_fee_schedule' limit 1) t
 where not exists (select 1 from pipeline.sources e where e.source_type='provider_fee_schedule' and e.metadata->>'provider_cricos'=x.cricos);

insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
select s.id, s.country_id, 'au_'||lower(s.metadata->>'provider_cricos')||'_intl_fee_schedule','provider_first_party',
       split_part(s.label,' international',1), s.metadata->>'provider_cricos', array['international_fee'],
       'exact CRICOS course code printed in the provider schedule, within the provider (Decision 149)',
       'schedule file retained as evidence with its SHA-256; one row per course; annual fee for one full-time year',
       'qualified','Decision 162 step 2: deterministic fee-schedule parser (v0.4.0); apply only after a clean dry run',
       jsonb_build_object('gate','Decision-162-fee-schedule','qualified_at',now(),'apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
  from pipeline.sources s
 where s.source_type='provider_fee_schedule' and s.metadata->>'provider_cricos' in ('00300K','00111D')
   and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id);
