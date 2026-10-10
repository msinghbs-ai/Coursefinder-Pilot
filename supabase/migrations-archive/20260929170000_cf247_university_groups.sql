-- CF-247: Australian university groups as provider collections (Platform Admin request 29 Sep 2026 13:19 IST).
-- Membership taken from each group's official member page on 29 Sep 2026:
--   Group of Eight (go8.edu.au/about/the-go8): Adelaide University, ANU, Melbourne, Monash, UNSW Sydney, UQ, Sydney, UWA
--   Australian Technology Network (atn.edu.au/our-members): Curtin, Deakin, UTS, RMIT, Newcastle
--   Innovative Research Universities (iru.edu.au/our-universities): Flinders, Griffith, JCU, La Trobe, Murdoch, Canberra, Western Sydney
--   Regional Universities Network (run.edu.au/about-us/run-universities): Charles Sturt, CQUniversity, Federation, Southern Cross, UNE, UniSQ
-- Members are matched to the university's own CRICOS provider code (pathway colleges and legacy pre-merger registrations
-- are not members). Membership is re-checked yearly (verified_at); changes go through a migration with the page cited.
insert into ref.institution_collections(code,name,collection_type,scope_type,country_id,official_url,description,status)
select v.code, v.name, 'university_group', 'provider', c.id, v.url, v.descr, 'active'
  from (values
    ('au_go8','Group of Eight','https://go8.edu.au/about/the-go8','Australia''s leading research-intensive universities'),
    ('au_atn','Australian Technology Network','https://www.atn.edu.au/our-members/','Technology-focused universities'),
    ('au_iru','Innovative Research Universities','https://iru.edu.au/our-universities/','Research universities with an innovation focus'),
    ('au_run','Regional Universities Network','https://run.edu.au/about-us/run-universities/','Regionally headquartered universities')) v(code,name,url,descr)
  cross join (select id from ref.countries where iso_alpha2='AU') c
on conflict (code) do update set name=excluded.name, official_url=excluded.official_url, description=excluded.description, updated_at=now();

insert into pipeline.sources(source_type,country_id,url,label,trust_rank,status,metadata)
select 'university_group_membership', ic.country_id, ic.official_url, ic.name||' - member universities', 95, 'active',
       jsonb_build_object('collection_code',ic.code,'checked','2026-09-29','decision','Decision 166')
  from ref.institution_collections ic
 where ic.collection_type='university_group'
   and not exists (select 1 from pipeline.sources s where s.source_type='university_group_membership' and s.metadata->>'collection_code'=ic.code);

with m(code,cricos) as (values
  ('au_go8','04249J'),('au_go8','00120C'),('au_go8','00116K'),('au_go8','00008C'),('au_go8','00098G'),('au_go8','00025B'),('au_go8','00026A'),('au_go8','00126G'),
  ('au_atn','00301J'),('au_atn','00113B'),('au_atn','00099F'),('au_atn','00122A'),('au_atn','00109J'),
  ('au_iru','00114A'),('au_iru','00233E'),('au_iru','00117J'),('au_iru','00115M'),('au_iru','00125J'),('au_iru','00212K'),('au_iru','00917K'),
  ('au_run','00005F'),('au_run','00219C'),('au_run','00103D'),('au_run','01241G'),('au_run','00003G'),('au_run','00244B'))
insert into catalogue.provider_collection_memberships(provider_id,collection_id,membership_type,status,valid_from,source_id,verified_at)
select pr.provider_id, ic.id, 'member', 'active', date '2026-09-29',
       (select s.id from pipeline.sources s where s.source_type='university_group_membership' and s.metadata->>'collection_code'=ic.code), now()
  from m join ref.institution_collections ic on ic.code=m.code
  join catalogue.provider_registrations pr on lower(pr.registration_scheme)='cricos' and upper(pr.registration_code)=m.cricos
 where not exists (select 1 from catalogue.provider_collection_memberships x where x.provider_id=pr.provider_id and x.collection_id=ic.id);

do $chk$ begin
  if (select count(*) from catalogue.provider_collection_memberships pcm join ref.institution_collections ic on ic.id=pcm.collection_id where ic.collection_type='university_group' and pcm.status='active')<>26 then
    raise exception 'expected 26 university-group memberships'; end if;
end $chk$;

-- read helper used by the consumer API and admin screens
create or replace function security.provider_university_groups(p_provider_id uuid)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','catalogue','ref' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('code',replace(ic.code,'au_',''),'name',ic.name) order by ic.name),'[]'::jsonb)
    from catalogue.provider_collection_memberships m join ref.institution_collections ic on ic.id=m.collection_id
   where m.provider_id=p_provider_id and m.status='active' and ic.collection_type='university_group' and ic.status='active'
     and (m.valid_to is null or m.valid_to>=current_date)
$f$;
