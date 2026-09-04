with catalogues(provider_name, catalogue_url) as (values
 ('The University of Melbourne (UniMelb)','https://scholarships.unimelb.edu.au/'),
 ('Australian National University','https://study.anu.edu.au/scholarships'),
 ('Monash University','https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship')
)
update pipeline.scholarship_acquisition_trace t
set first_party_catalogue_url = c.catalogue_url, updated_at = now()
from catalogue.providers p join catalogues c on c.provider_name=p.canonical_name
where t.provider_id=p.id and t.first_party_catalogue_url is null;

insert into pipeline.scholarship_acquisition_trace(provider_id,observed_title,first_party_catalogue_url,first_party_detail_url,stage,verification_status,verified_at,metadata)
select p.id, v.observed_title, v.catalogue_url, v.detail_url, 'first_party_verified','verified_first_party',now(),
       jsonb_build_object('authority','first_party','discovery_role','first_party_catalogue','change_control_ref','CF-CHG-20260904-108')
from (values
 ('The University of Melbourne (UniMelb)','Melbourne International Undergraduate Scholarship','https://scholarships.unimelb.edu.au/','https://scholarships.unimelb.edu.au/awards/melbourne-international-undergraduate-scholarship'),
 ('The University of Melbourne (UniMelb)','Melbourne International Excellence Scholarship (Undergraduate)','https://scholarships.unimelb.edu.au/','https://scholarships.unimelb.edu.au/awards/melbourne-international-excellence-scholarship-undergraduate'),
 ('The University of Melbourne (UniMelb)','Melbourne International Pathway Scholarship','https://scholarships.unimelb.edu.au/','https://scholarships.unimelb.edu.au/awards/melbourne-international-pathway-scholarship'),
 ('Australian National University','ANU Vice-Chancellor’s International Achievement Award','https://study.anu.edu.au/scholarships','https://study.anu.edu.au/scholarships/find-scholarship/anu-vice-chancellors-international-achievement-award'),
 ('Monash University','Monash International Leadership Scholarship','https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship','https://www.monash.edu/study/fees-scholarships/scholarships/find-a-scholarship/monash-international-leadership-scholarship-5571Z')
) as v(provider_name,observed_title,catalogue_url,detail_url)
join catalogue.providers p on p.canonical_name=v.provider_name
where not exists (
 select 1 from pipeline.scholarship_acquisition_trace t
 where t.provider_id=p.id and lower(t.observed_title)=lower(v.observed_title)
);
