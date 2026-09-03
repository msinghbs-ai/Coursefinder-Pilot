begin;

with overrides(provider_id,source_url,asset_url,basis) as (values
 ('e47a940d-186f-4a17-bb22-2b794b73248c'::uuid,'https://services.anu.edu.au/marketing-outreach/anu-identity/anu-logo/logo-use-standards','https://marketing-pages.anu.edu.au/_anu/4/images/logos/anu_logo_print.png','ANU official identity / logo-use standards'),
 ('c5c5d225-3d4c-4e41-8275-78eddd261073'::uuid,'https://www.deakin.edu.au/','https://study.deakin.edu.au/assets/img/svg/deakin-logo-with-text.svg','Deakin first-party study-site master logo'),
 ('fe6af182-f5ca-4a3c-bfb4-b0773ff1b113'::uuid,'https://www.jcu.edu.au/engage/sponsorships-and-brand-partnerships/images-logos','https://www.jcu.edu.au/_design/JCU-Logo-Horizontal-CMYK.svg','JCU official images/logos page'),
 ('188103a5-1aba-4f99-bd3e-0416659086d3'::uuid,'https://www.mq.edu.au/media/images','https://www.mq.edu.au/__data/assets/image/0015/1158/mqu-logo-horizontal.png','Macquarie official media images page'),
 ('543b87b8-f0dd-4bc7-80d6-76252cfaabec'::uuid,'https://www.monash.edu/brandbook/brand-elements/our-logo','https://www.monash.edu/__data/assets/image/0005/1738949/monash-university-stacked-blue.jpg','Monash official brandbook logo'),
 ('4f86e09a-557c-4544-a0a3-3eb5dc8468a9'::uuid,'https://www.latrobe.edu.au/about/at-a-glance/history/logo','https://www.latrobe.edu.au/about/at-a-glance/ds-images/la-trobe-university-logo3.jpg','La Trobe official logo history/identity page'),
 ('6f5cb7f7-7c70-4c06-970f-f368c3a786e2'::uuid,'https://dev.az.cdu.edu.au/brand/style-guide/logos','https://www.cdu.edu.au/images/cdu-logo-og.jpg','CDU official brand style-guide logo'),
 ('f30cd2cd-01fc-458e-a061-b7aa5faa8a00'::uuid,'https://www.scu.edu.au/','https://www.scu.edu.au/media/dep-site-assets/images/logo-print.420af8f0.png','Southern Cross first-party print/master logo asset'),
 ('62e61a02-9fcb-4c5e-bb11-1c43bed6eee6'::uuid,'https://www.uow.edu.au/','https://www.uow.edu.au/assets/logos/logo-svgs/logo-horizontal.svg','UOW first-party horizontal master logo'),
 ('de6d32b0-f91b-4dd0-a3da-a542f1aba5f2'::uuid,'https://designsystem.web.unimelb.edu.au/components/logo-listing/','https://designsystem.web.unimelb.edu.au/static/img/logo-icon.svg','University of Melbourne official Gen3 Design System logo')
)
insert into pipeline.provider_asset_candidates(provider_id,profile_id,source_url,asset_url,asset_type,evidence_id,confidence,status,metadata)
select o.provider_id,
 (select sp.id from pipeline.layer2_source_profiles sp join pipeline.sources s on s.id=sp.source_id where s.provider_id=o.provider_id and sp.domain='provider_asset' and sp.enabled and not sp.paused order by sp.updated_at desc limit 1),
 o.source_url,o.asset_url,'logo',null,0.99,'accepted',
 jsonb_build_object('mapping_method','official_brand_asset_override','evidence_basis','first_party_brand_or_design_system_asset','basis',o.basis,'verified_at',now(),'change_control_ref','CF-CHG-20260903-101','canonical_mutation_authorised',false)
from overrides o
on conflict(provider_id,asset_url) do update set
 source_url=excluded.source_url,confidence=0.99,status='accepted',
 metadata=coalesce(pipeline.provider_asset_candidates.metadata,'{}'::jsonb)||excluded.metadata,discovered_at=now();

commit;
