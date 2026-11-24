-- CF-247 F-AER.08 s1044 — Wave 3, fifteen NZ/CA providers: ten official source candidates,
-- five remain HELD:NO_SOURCE in Admin because no country-specific academic matrix is proved.
-- Guards: S3 owns NZ/CA only; AU untouched; 7,585 manual locks immutable; G3 75/48 frozen;
--        s1041 CA eligibility must already be released; no new cron, UI, AI, Firecrawl, reader policy.
-- Replaces: none. Retires: none.
-- Source correctness: UCOL's historical qualification PDF and Camosun's older viewbook
-- require edition verification; WITT's prospectus is not a proven country matrix.
-- Their acquisition never constitutes machine admission or permission to invent grades.
do $guard$
begin
  if to_regprocedure('security.entry_matrix_enabled_v1(uuid)') is null then
    raise exception 's1044 requires s1041 entry matrix eligibility function';
  end if;
  if position('k.iso_alpha2 = ''CA''' in pg_get_functiondef('security.entry_matrix_enabled_v1(uuid)'::regprocedure)) = 0 then
    raise exception 's1044 requires deployed s1041 scoped CA source eligibility (Pilot #1544 first)';
  end if;
end $guard$;

with rows(provider_id,url,title) as (
 values
 ('175462f3-59ea-4370-9c80-e7a06b100137'::uuid,'https://you.ubc.ca/applying-ubc/requirements/international-high-schools/','UBC international high-school country and degree requirements'),
 ('b509ab5c-87b2-4040-8385-d1ce610c7263'::uuid,'https://www.ulethbridge.ca/ross/admissions/undergrad/international','University of Lethbridge international undergraduate minimum academic requirements'),
 ('ad7bb2f7-ed12-4181-b5c4-d071db14bfda'::uuid,'https://www.ucalgary.ca/future-students/undergraduate/requirements','University of Calgary country and curriculum undergraduate admission requirements'),
 ('c79c40ee-0939-4e2e-b9b3-b4e2d772e667'::uuid,'https://durhamcollege.ca/info-for/international/study-dc/admission-requirements','Durham College international country and credential academic entry table'),
 ('4812a855-4fbc-43ce-9029-137c80327361'::uuid,'https://www.cna.nl.ca/Admissions/International/Getting-Started','College of the North Atlantic international academic entry and country criteria'),
 ('cc24d184-d9e1-4d8a-b6e5-812b3578d7ac'::uuid,'https://www.sheridancollege.ca/admissions/international/prospective-students/admission-requirements/','Sheridan College programme-specific international admission requirements'),
 ('30f2a374-62e8-4be5-81fd-b94f033ea937'::uuid,'https://camosun.ca/sites/default/files/2021-12/camosun-international-viewbook.pdf','Camosun international viewbook academic entry; edition verification required'),
 ('cffa9cab-0a3b-458b-8383-483ce622c9c3'::uuid,'https://umanitoba.ca/explore/undergraduate-admissions/requirements/international-admission-requirements','University of Manitoba country and programme academic minima'),
 ('adeb0bbb-5b07-4130-aaeb-ad404bf40ff7'::uuid,'https://www.ucol.ac.nz/media/c5qn2qji/international-entry-criteria.pdf','UCOL international qualifications entry criteria; OLD EDITION requires currency verification'),
 ('fd76fddc-fc8e-496d-bf89-c466d8efeb17'::uuid,'https://www.witt.ac.nz/assets/WITT-PDF-Documents/2026-Final-Prospectus-International.pdf','WITT 2026 international prospectus; programme entry only, not assumed matrix')
)
insert into pipeline.entry_matrix_sources(provider_id,url,title,rank,found_via)
select r.provider_id,r.url,r.title,1,'manual' from rows r
join catalogue.providers p on p.id=r.provider_id
join ref.countries k on k.id=p.country_id and k.iso_alpha2 in ('CA','NZ')
on conflict(provider_id,url) do nothing;

-- The four CA Wave 2 providers already in s1041 remain eligible.
-- Add just the eight Wave 3 CA providers; no global CA scheduled-country switch.
update pipeline.platform_toolset_settings s
   set value = (
     select to_jsonb(array(
       select distinct v from (
          select jsonb_array_elements_text(s.value) v
          union all
          select unnest(array[
            '175462f3-59ea-4370-9c80-e7a06b100137',
            'b509ab5c-87b2-4040-8385-d1ce610c7263',
            'ad7bb2f7-ed12-4181-b5c4-d071db14bfda',
            'c79c40ee-0939-4e2e-b9b3-b4e2d772e667',
            '4812a855-4fbc-43ce-9029-137c80327361',
            'cc24d184-d9e1-4d8a-b6e5-812b3578d7ac',
            '30f2a374-62e8-4be5-81fd-b94f033ea937',
            'cffa9cab-0a3b-458b-8383-483ce622c9c3'
          ]::text[])
       ) x order by v
     ))
   ),
   reason = 's1044 NZ/CA Wave 3: eight scoped CA official entry sources; no blanket Canadian schedule, five other NZ providers source-held'
where s.toolset_key='pipeline' and s.key='entry.providers' and jsonb_typeof(s.value)='array';

-- Evidence-first, NZ/CA only. Existing sources are found/unfetched, so runs may be
-- zero at migration time; the existing entry-matrix-read cron will fetch+enqueue them.
with cohort(provider_id) as (values
 ('175462f3-59ea-4370-9c80-e7a06b100137'::uuid),('b509ab5c-87b2-4040-8385-d1ce610c7263'::uuid),
 ('ad7bb2f7-ed12-4181-b5c4-d071db14bfda'::uuid),('c79c40ee-0939-4e2e-b9b3-b4e2d772e667'::uuid),
 ('4812a855-4fbc-43ce-9029-137c80327361'::uuid),('cc24d184-d9e1-4d8a-b6e5-812b3578d7ac'::uuid),
 ('30f2a374-62e8-4be5-81fd-b94f033ea937'::uuid),('cffa9cab-0a3b-458b-8383-483ce622c9c3'::uuid),
 ('adeb0bbb-5b07-4130-aaeb-ad404bf40ff7'::uuid),('fd76fddc-fc8e-496d-bf89-c466d8efeb17'::uuid))
insert into pipeline.entry_matrix_runs(provider_id,source_id,content_hash)
select s.provider_id,s.id,s.content_hash
from pipeline.entry_matrix_sources s join cohort c on c.provider_id=s.provider_id
where s.status='read' and s.content_hash is not null and s.evidence_id is not null
  and security.entry_matrix_enabled_v1(s.provider_id)
on conflict (source_id,content_hash) do nothing;

insert into pipeline.admin_control_events(area,action,target,detail,actor)
select 'aer','wave3_nzca_register','pipeline.entry_matrix_sources',
 jsonb_build_object('spec','s1044','providers_ranked',15,'sources_registered',10,
 'country','NZ,CA','canadian_wave3_allowlist',8,
 'holding_for_current_source',jsonb_build_array('NZIST Work-Based Learning','EIT','Toi Ohomai','NorthTec','Open Polytechnic'),
 'reason','24 Nov 2026 NZ/CA delegated Wave 3: evidence-first no guessed matrix, no AU changes'),
 auth.uid()
where not exists (select 1 from pipeline.admin_control_events e where e.area='aer' and e.action='wave3_nzca_register' and e.detail->>'spec'='s1044');

do $check$
begin
 if (security.aer_schedule_country_v1('CA')->>'on')::boolean then
   raise exception 's1044: CA country-wide scheduled AER must remain disabled';
 end if;
 if (select count(*) from cron.job where active)>140 then
   raise exception 's1044: G1 active cron ceiling breached';
 end if;
end $check$;
