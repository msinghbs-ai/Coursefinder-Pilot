begin;

with x(provider_id,source_url,asset_url,basis,source_class,archive_bundle) as (values
 ('030992c3-72c6-452d-8a3b-10ceb0fd77f2'::uuid,
  'https://www.acu.edu.au/',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/Australian_Catholic_University_logo_2024.svg',
  'Current ACU logo; public fallback corroborated by canonical Provider identity and Hotcourses institution match',
  'official_derived_public_asset',false),
 ('36086f5e-9fe0-4878-aa40-1897a7d8cb24'::uuid,
  'https://www.griffith.edu.au/marketing-communications/design-studio',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/Griffith_University_Logo_Variant_2023.svg',
  'Current Griffith University logo; official brand guidance corroboration',
  'official_derived_public_asset',false),
 ('2c4f515c-c146-4e90-ba8a-294130aa1f40'::uuid,
  'https://www.qut.edu.au/study/international/for-agents/marketing-resources',
  'https://cms.qut.edu.au/__data/assets/file/0005/849362/QUTI-logos.zip',
  'QUT official international logo bundle published for agents',
  'first_party_official_bundle',true),
 ('dce54a01-39c1-4bdf-877d-b67da3afc81e'::uuid,
  'https://www.notredame.edu.au/',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/The_University_of_Notre_Dame_Australia_Logo.svg',
  'Current Notre Dame Australia logo; official identity corroboration',
  'official_derived_public_asset',false),
 ('fa0e0d13-838a-42ff-b6a3-9cea84bd80b2'::uuid,
  'https://www.une.edu.au/brand-toolkit',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/Logo_of_the_University_of_New_England_(Australia).svg',
  'UNE logo sourced from University of New England and corroborated by official brand toolkit',
  'official_derived_public_asset',false),
 ('719403bc-6957-4d21-af69-2b3b102df578'::uuid,
  'https://www.utas.edu.au/',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/UniversityofTasmaniaLogo.svg',
  'University of Tasmania current logo fallback, canonical Provider corroborated',
  'official_derived_public_asset',false),
 ('39301fa8-bff2-4389-bbcd-32d8415fae04'::uuid,
  'https://www.aut.ac.nz/',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/Logo_of_Auckland_University_of_Technology.svg',
  'AUT logo sourced from official AUT material; public-domain text/logo fallback',
  'official_derived_public_asset',false),
 ('ab12c7f8-e368-453d-9dfe-4ab8bd744829'::uuid,
  'https://www.otago.ac.nz/marketing-services/resources/university-of-otago-brand-guide',
  'https://commons.wikimedia.org/wiki/Special:Redirect/file/University_of_Otago_logo_2024.svg',
  'Current 2024 University of Otago wordmark corroborated by official current brand guide',
  'official_derived_public_asset',false)
)
insert into pipeline.provider_asset_candidates(
 provider_id,profile_id,source_url,asset_url,asset_type,evidence_id,content_hash,confidence,status,metadata
)
select x.provider_id,
 (select sp.id from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id
   where s.provider_id=x.provider_id and sp.domain='provider_asset' and sp.enabled and not sp.paused
   order by case when s.source_type='web_catalogue' then 0 else 1 end,s.trust_rank desc nulls last,sp.updated_at desc limit 1),
 x.source_url,x.asset_url,'logo',null,null,0.99,'accepted',
 jsonb_build_object(
   'mapping_method','cf101_exact_logo_fallback',
   'source_class',x.source_class,
   'basis',x.basis,
   'operator_fallback_reuse_approved',true,
   'canonical_owner','provider',
   'hotcourses_corroborated',true,
   'archive_bundle',x.archive_bundle,
   'archive_member_selection',case when x.archive_bundle then 'best QUT logo image by filename score' else null end,
   'change_control_ref','CF-CHG-20260903-101',
   'canonical_mutation_authorised',false
 )
from x
on conflict(provider_id,asset_url) do update set
 source_url=excluded.source_url,confidence=excluded.confidence,status='accepted',
 metadata=coalesce(pipeline.provider_asset_candidates.metadata,'{}'::jsonb)||excluded.metadata,
 discovered_at=now();

commit;
