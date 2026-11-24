-- CF-247 F-AER.08 s1045 (S3-AER-ChatGPT NZ/CA Wave 4, Platform Admin 24 Nov 2026).
-- 45 NZ/CA providers: 32 source-backed claims, 12 HELD:NO_SOURCE, one HELD:SITE_BLOCKED.
-- 22 first-party academic admissions source candidates already registered live; 11 older sources reused.
-- Guards: requires s1044 deployed; G3 (75 consumer funcs/48 relations) unchanged, zero AU,
-- 7,585 manual locks unchanged, <=140 active cron, no UI, no blank hashes, no fabricated grades.
-- Replaces: nothing (data-only existing pipeline tables/settings).
-- Retires: nothing.
-- This is source candidate and queue registration only. Human Layer 4 decisions remain unchanged.
do $g$
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='20261124203000') then
  raise exception 's1045 requires Wave 3 migration 20261124203000 to deploy first';
 end if;
 if (select count(*) from cron.job where active)>140 then
  raise exception 's1045 active cron ceiling exceeded';
 end if;
end $g$;

with source_rows(provider_id,url,title) as (values
('5b6ad653-99f7-4347-a56e-f0d2928bd34d'::uuid,'https://www.okanagancollege.ca/international/international-students-application-guide','Okanagan College international country/region academic admissions guide'),
('7b493f26-269e-4d7e-94ae-ede842d96335'::uuid,'https://www.tru.ca/future/admissions/international/admission-requirements.html','Thompson Rivers University international academic admission requirements'),
('0d47cf4f-7389-4d92-b7a7-8a2eba6ea1e6'::uuid,'https://www.unbc.ca/programs-and-admissions/undergraduate/international-admission-requirements-undergraduate-studies','UNBC country-specific international high-school academic requirements'),
('e924fe06-feb7-472b-9035-4ccebdf9fe67'::uuid,'https://media.cambriancollege.ca/uploads/2025/09/10095058/Admissions-Policy-2025_FINAL-1.pdf','Cambrian College 2025 academic eligibility and programme admissions policy - not country matrix'),
('4682bc05-a9de-44bb-ae66-ad02c9717a2d'::uuid,'https://www.algonquincollege.com/international/admission-requirements/','Algonquin College country-by-credential international academic entry requirements'),
('6907453a-faa4-4c60-bc64-e2f2ea476a15'::uuid,'https://loyalistcollege.com/admissions/how-to-apply/admission-requirements/','Loyalist College international academic admission requirements and programme rules'),
('e450a320-27d7-4ca2-8ad6-cafa266df869'::uuid,'https://www.athabascau.ca/applications-admissions/apply-au/international-students.html','Athabasca University international admissions and academic credentials'),
('dc671c35-5660-48ff-bb3b-31be971c0d9f'::uuid,'https://www.georgebrown.ca/international/future-students/admission-requirements','George Brown Polytechnic international academic qualifications by country'),
('50efbfe2-b917-4cf7-be50-4a53c9a718d7'::uuid,'https://www.macewan.ca/academics/programs/bachelor-of-arts/admissions/requirements/index.html','MacEwan Bachelor of Arts international secondary academic entry - programme scoped'),
('3273618f-8b4c-4584-bead-3ba193d84b1e'::uuid,'https://international.ufv.ca/future-students/apply-to-ufv/admission-requirements/','University of Fraser Valley international admission and equivalent secondary qualifications'),
('fd7048c4-9a0c-4c6f-818b-94ab6f6d809d'::uuid,'https://www.viu.ca/admissions/international','Vancouver Island University international undergraduate and graduate academic requirements'),
('89bab0e8-22c2-431b-8da4-ebf8ffbe5cdb'::uuid,'https://langara.ca/apply/apply-regular-studies/admission-requirements','Langara international BC Grade 12 equivalency academic admission'),
('570ddbbd-f07e-4060-b52d-c5322dcdaa00'::uuid,'https://academic-regulations.humber.ca/2025-2026/5.0-ADMISSION','Humber 2025-26 international academic admissions policy - equivalencies elsewhere'),
('d38d9f8a-c2f1-446c-9d1d-6410ff878375'::uuid,'https://www.mtroyal.ca/InternationalStudents/Admissionrequirements/','Mount Royal University international academic admission requirements'),
('6c7c4d60-18c0-4fe7-9428-6f911c475dac'::uuid,'https://cat.georgiancollege.ca/academic-regulations/admissions/','Georgian College international academic admission regulations'),
('3e436a48-1f61-4690-9fbd-4c749f3acfef'::uuid,'https://www.kpu.ca/admission/out-of-country','KPU international country-specific transcript qualification requirements'),
('57695444-f503-48fe-a762-eb1898ec5c5a'::uuid,'https://www.royalroads.ca/future-students/international-students/international-student-admission/country-specific-admission','Royal Roads University academic entry by country and level'),
('5e1a25b3-94d3-4e9a-8cc1-98dacd3bfd62'::uuid,'https://uploads.up.education/wp-content/uploads/2026/02/UP-Cheat-Sheet-2026-WEB-100226.pdf','NZMA parent education group 2026 international academic entry per programme - requires scope check'),
('f145b8e9-36dd-4f96-b1f5-bb453ced3a45'::uuid,'https://www.wananga.com/apply-now','Te Wananga o Raukawa current academic entry regulations - general, no country table'),
('29fabe13-e9fe-497c-ae2b-bd6d08b5c46b'::uuid,'https://www.whitecliffe.ac.nz/apply/international-students/','Whitecliffe NZ official international academic entry PDF landing page'),
('5675f806-596a-4982-bd4a-f068e013f974'::uuid,'https://www.collegelacite.ca/documents/10315/30925002/Guide-des-programmes-international.pdf','La Cite official international programmes: minimum secondary equivalence, IB DP 24, programme requirements'),
('fe2e938f-4e46-427f-ac1b-73a650b1a14d'::uuid,'https://nzse.ac.nz/enrolment/how-to-apply/','NZ School of Education official international general academic enrolment criteria; programme rules separate')
)
insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
select s.provider_id,s.url,left(s.title,200),1,'manual'
from source_rows s join catalogue.providers p on p.id=s.provider_id
 join ref.countries c on c.id=p.country_id and c.iso_alpha2 in ('NZ','CA')
on conflict(provider_id,url) do nothing;

-- Add only the Wave 4 CA providers with verified first-party source candidates;
-- never enable CA globally. Existing Wave 2/3 provider IDs stay in this list.
update pipeline.platform_toolset_settings s set
 value=(select to_jsonb(array(select distinct v from (
    select jsonb_array_elements_text(s.value) v
    union all select unnest(array['5b6ad653-99f7-4347-a56e-f0d2928bd34d','7b493f26-269e-4d7e-94ae-ede842d96335','0d47cf4f-7389-4d92-b7a7-8a2eba6ea1e6','e924fe06-feb7-472b-9035-4ccebdf9fe67','4682bc05-a9de-44bb-ae66-ad02c9717a2d','6907453a-faa4-4c60-bc64-e2f2ea476a15','e450a320-27d7-4ca2-8ad6-cafa266df869','dc671c35-5660-48ff-bb3b-31be971c0d9f','50efbfe2-b917-4cf7-be50-4a53c9a718d7','3273618f-8b4c-4584-bead-3ba193d84b1e','fd7048c4-9a0c-4c6f-818b-94ab6f6d809d','89bab0e8-22c2-431b-8da4-ebf8ffbe5cdb','570ddbbd-f07e-4060-b52d-c5322dcdaa00','d38d9f8a-c2f1-446c-9d1d-6410ff878375','6c7c4d60-18c0-4fe7-9428-6f911c475dac','3e436a48-1f61-4690-9fbd-4c749f3acfef','57695444-f503-48fe-a762-eb1898ec5c5a','5675f806-596a-4982-bd4a-f068e013f974']::text[])
 ) vals order by v))),
 reason='s1045 NZ/CA Wave 4: scoped CA AER for source-backed providers; no blanket country activation'
where s.toolset_key='pipeline' and s.key='entry.providers' and jsonb_typeof(s.value)='array';

-- Only existing stored evidence can become a runnable matrix, never an invented content hash.
-- Existing (source_id,content_hash) runs remain unchanged, including human-held Layer 4 decisions.
with cohort(provider_id) as (values
('5b6ad653-99f7-4347-a56e-f0d2928bd34d'::uuid),
('7b493f26-269e-4d7e-94ae-ede842d96335'::uuid),
('0d47cf4f-7389-4d92-b7a7-8a2eba6ea1e6'::uuid),
('e924fe06-feb7-472b-9035-4ccebdf9fe67'::uuid),
('4682bc05-a9de-44bb-ae66-ad02c9717a2d'::uuid),
('6907453a-faa4-4c60-bc64-e2f2ea476a15'::uuid),
('e450a320-27d7-4ca2-8ad6-cafa266df869'::uuid),
('dc671c35-5660-48ff-bb3b-31be971c0d9f'::uuid),
('50efbfe2-b917-4cf7-be50-4a53c9a718d7'::uuid),
('3273618f-8b4c-4584-bead-3ba193d84b1e'::uuid),
('fd7048c4-9a0c-4c6f-818b-94ab6f6d809d'::uuid),
('89bab0e8-22c2-431b-8da4-ebf8ffbe5cdb'::uuid),
('570ddbbd-f07e-4060-b52d-c5322dcdaa00'::uuid),
('d38d9f8a-c2f1-446c-9d1d-6410ff878375'::uuid),
('6c7c4d60-18c0-4fe7-9428-6f911c475dac'::uuid),
('3e436a48-1f61-4690-9fbd-4c749f3acfef'::uuid),
('57695444-f503-48fe-a762-eb1898ec5c5a'::uuid),
('5e1a25b3-94d3-4e9a-8cc1-98dacd3bfd62'::uuid),
('f145b8e9-36dd-4f96-b1f5-bb453ced3a45'::uuid),
('29fabe13-e9fe-497c-ae2b-bd6d08b5c46b'::uuid),
('5675f806-596a-4982-bd4a-f068e013f974'::uuid),
('fe2e938f-4e46-427f-ac1b-73a650b1a14d'::uuid)
)
insert into pipeline.entry_matrix_runs(provider_id,source_id,content_hash)
select src.provider_id,src.id,src.content_hash
from cohort c join pipeline.entry_matrix_sources src on src.provider_id=c.provider_id
where src.status='read' and src.evidence_id is not null and src.content_hash is not null
 and security.entry_matrix_enabled_v1(src.provider_id)
 and not exists (select 1 from pipeline.entry_matrix_runs r where r.source_id=src.id and r.content_hash is not distinct from src.content_hash)
on conflict(source_id,content_hash) do nothing;

insert into pipeline.admin_control_events(area,action,target,detail,actor)
select 'aer','wave4_nzca_register','pipeline.entry_matrix_sources',
 jsonb_build_object('spec','s1045','lane','S3-AER-ChatGPT','cohort',45,
 'source_backed_claims',32,'source_holds',12,'robots_holds',1,
 'new_sources',22,'ca_allowlist_additions',18,'model_calls',0,
 'reason','NZ/CA official source candidates and guarded evidence-only enqueue; AU and Layer 4 immutable'),
 auth.uid()
where not exists(select 1 from pipeline.admin_control_events e
 where e.area='aer' and e.action='wave4_nzca_register' and e.detail->>'spec'='s1045');

do $p$
begin
 if (security.aer_schedule_country_v1('CA')->>'on')::boolean then
  raise exception 's1045 must not activate CA-wide AER schedule';
 end if;
 if (select count(*) from cron.job where active)>140 then
  raise exception 's1045 active cron ceiling breached';
 end if;
end $p$;
