insert into ref.study_levels(code,name,sort_order) values ('associate_degree','Associate Degree',35) on conflict(code) do nothing;

insert into ref.fields_of_study(code,name,path,depth) values
('computer-science','Computer Science','computer-science',0),
('information-systems','Information Systems','information-systems',0),
('other-information-technology','Other Information Technology','other-information-technology',0),
('mathematical-sciences','Mathematical Sciences','mathematical-sciences',0),
('other-natural-physical-sciences','Other Natural and Physical Sciences','other-natural-physical-sciences',0),
('architecture-urban-environment','Architecture and Urban Environment','architecture-urban-environment',0),
('business-management','Business and Management','business-management',0),
('banking-finance-related','Banking, Finance and Related Fields','banking-finance-related',0),
('other-society-culture','Other Society and Culture','other-society-culture',0),
('natural-physical-sciences','Natural and Physical Sciences','natural-physical-sciences',0),
('management-commerce','Management and Commerce','management-commerce',0)
on conflict(code) do nothing;

insert into workflow.migration_runs(id,source_environment,source_project_ref,migration_scope,status,started_at,completed_at,notes,metrics)
values('11111111-1111-4111-8111-111111111111','coursefinder-demo','gfryvshbeptxwbzjomhe','ui_seed_slice','completed',now(),now(),'Validated seven-provider UI seed from demo',jsonb_build_object('providers',7,'courses',35))
on conflict(id) do nothing;

with f as (select id from pim.attribute_families where code='provider_default')
insert into pim.entity_registry(id,entity_type,stable_key,family_id,lifecycle_status)
select v.id,'provider','provider:demo:'||v.id::text,f.id,'active'
from f cross join (values
('edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid),
('6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid),
('6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid),
('7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid),
('3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid),
('2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid),
('00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid)
) v(id) on conflict(id) do nothing;

insert into catalogue.providers(id,stable_key,canonical_name,display_name,country_id,provider_type_id,website,primary_city,lifecycle_status,publication_status)
select v.id,'provider:demo:'||v.id::text,v.name,v.name,c.id,pt.id,v.website,v.city,'active','published'
from (values
('edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Adelaide University',null::text,'Adelaide'),
('6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Monash University','https://www.monash.edu.au','Clayton'),
('6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'RMIT University (RMIT)','https://www.rmit.edu.au','Melbourne'),
('7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'The University of Melbourne (UniMelb)','http://www.unimelb.edu.au/','Parkville'),
('3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'The University of Sydney','http://sydney.edu.au','Sydney'),
('2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'University of Technology Sydney (UTS)','https://www.uts.edu.au','Broadway'),
('00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'UNSW Sydney','https://www.unsw.edu.au','Kensington')
) v(id,name,website,city)
join ref.countries c on c.iso_alpha2='AU' join ref.provider_types pt on pt.code='university'
on conflict(id) do nothing;

with f as (select id from pim.attribute_families where code='course_default'), src(id,provider_id,title,level_code,field_name,weeks,delivery) as (values
('da7dd3c0-9e0b-4d8b-a677-4ecfb4fdf7a1'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Cyber Security','associate_degree','Other Information Technology',104.0,'on_campus'),
('f22c5591-9b57-480d-a161-3ff77fe2f1c7'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Data Analytics','associate_degree','Mathematical Sciences',104.0,'on_campus'),
('cb554dd4-997b-435a-8173-20753fdd4790'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Information Technology','associate_degree','Other Information Technology',104.0,'on_campus'),
('03f7169b-13c7-4352-8e66-f86356cc4a50'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Bachelor of Applied Data Analytics','bachelor','Other Natural and Physical Sciences',156.0,'on_campus'),
('7b2b20ba-2ba9-4dec-a36e-cdb33a930d6c'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Bachelor of Commerce, Bachelor of Mathematical and Computer Sciences','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('93e73f76-ba7c-4d18-97de-aade8beb7ed5'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Applied Data Science','bachelor','Mathematical Sciences',156.0,'on_campus'),
('349e16d5-d909-40a5-b6ab-c8ba37c6e27b'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Applied Data Science Advanced (Honours)','bachelor','Mathematical Sciences',208.0,'on_campus'),
('df33bdf3-42ec-414c-bf75-734b36d850cf'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Architectural Studies and Bachelor of Information Technology','bachelor','Architecture and Urban Environment',208.0,'on_campus'),
('7452c769-386e-44e3-a954-f6dfbbe5c965'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Artificial Intelligence','bachelor','Computer Science',158.0,'on_campus'),
('c630d7b9-931f-4516-940d-4402f436eb2e'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Business and Bachelor of Information Technology','bachelor','Business and Management',208.0,'on_campus'),
('c202257f-fe71-465a-b3b7-7f5497d4b5eb'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Associate Degree in Information Technology','associate_degree','Other Information Technology',104.0,'on_campus'),
('4c68738e-9b9c-4b98-9bf0-37916d4a1533'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Business (Information Systems)','bachelor','Information Systems',156.0,'on_campus'),
('49d4fc30-4f81-443b-88e0-3a6e1be46b78'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Business (Information Systems)(Applied)','bachelor','Information Systems',208.0,'on_campus'),
('b0625999-99bd-41a1-b561-627f5cc40430'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Computer Science','bachelor','Computer Science',156.0,'on_campus'),
('2ec4fe63-3652-4500-8002-2ced892a4c9c'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Computer Science (Honours)','bachelor','Computer Science',52.0,'on_campus'),
('d2f3eb2d-9c30-4ebd-ba50-43d16fcd985d'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Computer Science','graduate_certificate','Computer Science',26.0,'on_campus'),
('69073d07-9cf1-4617-81b8-a4b41d2cd415'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Information Systems','graduate_certificate','Information Systems',26.0,'on_campus'),
('4919f4e2-89c3-4f7b-b8f1-d62577c773ba'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Information Systems (Advanced)','graduate_certificate','Information Systems',26.0,'on_campus'),
('896dee33-07e4-46cb-be5c-68a3f9142c82'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Diploma in Computer Science','graduate_diploma','Computer Science',52.0,'on_campus'),
('b10f0d3a-b90d-4a03-bd7e-524aad033b73'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Diploma in Foundational Data Science','graduate_diploma','Computer Science',52.0,'on_campus'),
('c2d5db02-609d-4f8e-8c0a-2926892396ca'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Computer Science and Technology','bachelor','Computer Science',156.0,'on_campus'),
('0eb967f0-ed8b-4f2a-9cfc-50518e3d2314'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Computer Science and Technology (Honours)','bachelor','Computer Science',52.0,'on_campus'),
('083971b0-ee74-4a75-bd7e-431a3a2a7f76'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technologies and Bachelor of Commerce','bachelor','Other Information Technology',260.0,'on_campus'),
('ca437ac2-c76b-4916-bea5-b9446fc1c017'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technology','bachelor','Other Information Technology',208.0,'on_campus'),
('43f65251-56d9-47f7-8e1a-943884310956'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technology and Bachelor of Arts','bachelor','Other Information Technology',260.0,'on_campus'),
('ed296a1f-48d7-4c96-b6c9-2934dcae02ae'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence','bachelor','Computer Science',156.0,'on_campus'),
('1d2359d1-fc7d-4b2b-bbf5-0073e7cea3d4'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence Bachelor of International Studies','bachelor','Computer Science',260.0,'on_campus'),
('8de5264d-1ad7-43e3-8a52-e1bfc4bc9604'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence Bachelor of International Studies (Honours)','bachelor','Computer Science',260.0,'on_campus'),
('a22897ff-63bb-4243-8abd-15404781e21e'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Criminology Bachelor of Cybersecurity','bachelor','Other Society and Culture',208.0,'on_campus'),
('5ca5dffc-890f-4a95-ba0f-6c9ea14ee527'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Cybersecurity','bachelor','Other Information Technology',156.0,'on_campus'),
('d8094363-7a85-40c9-8093-c89df7bb5e10'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Actuarial Studies / Bachelor of Information Systems','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('520d0e43-ab5c-456b-b777-43a4cca4c654'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Actuarial Studies / Bachelor of Science (Computer Science)','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('c8ac9f9f-7810-4ec1-b038-0392dc1c0941'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Advanced Computer Science (Honours)','bachelor','Computer Science',208.0,'on_campus'),
('d55784f1-694d-4614-b593-15288ee1ecd3'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Advanced Science (Honours)/Bachelor of Science (Computer Science)','bachelor','Natural and Physical Sciences',260.0,'on_campus'),
('a7b3f8f6-845a-481c-ae2d-da7456738ff7'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Commerce/Bachelor of Information Systems','bachelor','Management and Commerce',208.0,'on_campus')
)
insert into pim.entity_registry(id,entity_type,stable_key,family_id,lifecycle_status)
select s.id,'course','course:demo:'||s.id::text,f.id,'active' from src s cross join f on conflict(id) do nothing;

with src(id,provider_id,title,level_code,field_name,weeks,delivery) as (values
('da7dd3c0-9e0b-4d8b-a677-4ecfb4fdf7a1'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Cyber Security','associate_degree','Other Information Technology',104.0,'on_campus'),
('f22c5591-9b57-480d-a161-3ff77fe2f1c7'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Data Analytics','associate_degree','Mathematical Sciences',104.0,'on_campus'),
('cb554dd4-997b-435a-8173-20753fdd4790'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Associate Degree in Information Technology','associate_degree','Other Information Technology',104.0,'on_campus'),
('03f7169b-13c7-4352-8e66-f86356cc4a50'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Bachelor of Applied Data Analytics','bachelor','Other Natural and Physical Sciences',156.0,'on_campus'),
('7b2b20ba-2ba9-4dec-a36e-cdb33a930d6c'::uuid,'edd81a77-3d3c-4c86-8b05-54862436f7b8'::uuid,'Bachelor of Commerce, Bachelor of Mathematical and Computer Sciences','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('93e73f76-ba7c-4d18-97de-aade8beb7ed5'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Applied Data Science','bachelor','Mathematical Sciences',156.0,'on_campus'),
('349e16d5-d909-40a5-b6ab-c8ba37c6e27b'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Applied Data Science Advanced (Honours)','bachelor','Mathematical Sciences',208.0,'on_campus'),
('df33bdf3-42ec-414c-bf75-734b36d850cf'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Architectural Studies and Bachelor of Information Technology','bachelor','Architecture and Urban Environment',208.0,'on_campus'),
('7452c769-386e-44e3-a954-f6dfbbe5c965'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Artificial Intelligence','bachelor','Computer Science',158.0,'on_campus'),
('c630d7b9-931f-4516-940d-4402f436eb2e'::uuid,'6ccd623e-a902-40fe-b809-c4a19c8a2610'::uuid,'Bachelor of Business and Bachelor of Information Technology','bachelor','Business and Management',208.0,'on_campus'),
('c202257f-fe71-465a-b3b7-7f5497d4b5eb'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Associate Degree in Information Technology','associate_degree','Other Information Technology',104.0,'on_campus'),
('4c68738e-9b9c-4b98-9bf0-37916d4a1533'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Business (Information Systems)','bachelor','Information Systems',156.0,'on_campus'),
('49d4fc30-4f81-443b-88e0-3a6e1be46b78'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Business (Information Systems)(Applied)','bachelor','Information Systems',208.0,'on_campus'),
('b0625999-99bd-41a1-b561-627f5cc40430'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Computer Science','bachelor','Computer Science',156.0,'on_campus'),
('2ec4fe63-3652-4500-8002-2ced892a4c9c'::uuid,'6a8bbe02-3cfc-483d-813e-cc8975c2206f'::uuid,'Bachelor of Computer Science (Honours)','bachelor','Computer Science',52.0,'on_campus'),
('d2f3eb2d-9c30-4ebd-ba50-43d16fcd985d'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Computer Science','graduate_certificate','Computer Science',26.0,'on_campus'),
('69073d07-9cf1-4617-81b8-a4b41d2cd415'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Information Systems','graduate_certificate','Information Systems',26.0,'on_campus'),
('4919f4e2-89c3-4f7b-b8f1-d62577c773ba'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Certificate in Information Systems (Advanced)','graduate_certificate','Information Systems',26.0,'on_campus'),
('896dee33-07e4-46cb-be5c-68a3f9142c82'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Diploma in Computer Science','graduate_diploma','Computer Science',52.0,'on_campus'),
('b10f0d3a-b90d-4a03-bd7e-524aad033b73'::uuid,'7a572aad-502b-4d5d-8388-f1ed249575cf'::uuid,'Graduate Diploma in Foundational Data Science','graduate_diploma','Computer Science',52.0,'on_campus'),
('c2d5db02-609d-4f8e-8c0a-2926892396ca'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Computer Science and Technology','bachelor','Computer Science',156.0,'on_campus'),
('0eb967f0-ed8b-4f2a-9cfc-50518e3d2314'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Computer Science and Technology (Honours)','bachelor','Computer Science',52.0,'on_campus'),
('083971b0-ee74-4a75-bd7e-431a3a2a7f76'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technologies and Bachelor of Commerce','bachelor','Other Information Technology',260.0,'on_campus'),
('ca437ac2-c76b-4916-bea5-b9446fc1c017'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technology','bachelor','Other Information Technology',208.0,'on_campus'),
('43f65251-56d9-47f7-8e1a-943884310956'::uuid,'3ac488f2-00c7-430f-afdf-4b35f090885f'::uuid,'Bachelor of Information Technology and Bachelor of Arts','bachelor','Other Information Technology',260.0,'on_campus'),
('ed296a1f-48d7-4c96-b6c9-2934dcae02ae'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence','bachelor','Computer Science',156.0,'on_campus'),
('1d2359d1-fc7d-4b2b-bbf5-0073e7cea3d4'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence Bachelor of International Studies','bachelor','Computer Science',260.0,'on_campus'),
('8de5264d-1ad7-43e3-8a52-e1bfc4bc9604'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Artificial Intelligence Bachelor of International Studies (Honours)','bachelor','Computer Science',260.0,'on_campus'),
('a22897ff-63bb-4243-8abd-15404781e21e'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Criminology Bachelor of Cybersecurity','bachelor','Other Society and Culture',208.0,'on_campus'),
('5ca5dffc-890f-4a95-ba0f-6c9ea14ee527'::uuid,'2e7d2c0c-af2c-4f59-bb7a-806b36f1ad2e'::uuid,'Bachelor of Cybersecurity','bachelor','Other Information Technology',156.0,'on_campus'),
('d8094363-7a85-40c9-8093-c89df7bb5e10'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Actuarial Studies / Bachelor of Information Systems','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('520d0e43-ab5c-456b-b777-43a4cca4c654'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Actuarial Studies / Bachelor of Science (Computer Science)','bachelor','Banking, Finance and Related Fields',208.0,'on_campus'),
('c8ac9f9f-7810-4ec1-b038-0392dc1c0941'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Advanced Computer Science (Honours)','bachelor','Computer Science',208.0,'on_campus'),
('d55784f1-694d-4614-b593-15288ee1ecd3'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Advanced Science (Honours)/Bachelor of Science (Computer Science)','bachelor','Natural and Physical Sciences',260.0,'on_campus'),
('a7b3f8f6-845a-481c-ae2d-da7456738ff7'::uuid,'00958ac1-0abd-4dab-9c9a-9b10a28a5d04'::uuid,'Bachelor of Commerce/Bachelor of Information Systems','bachelor','Management and Commerce',208.0,'on_campus')
)
insert into catalogue.courses(id,stable_key,provider_id,canonical_title,display_title,study_level_id,primary_field_id,duration_value,duration_unit,delivery_mode,lifecycle_status,publication_status)
select s.id,'course:demo:'||s.id::text,s.provider_id,s.title,s.title,sl.id,fos.id,s.weeks,'weeks',s.delivery,'active','published'
from src s left join ref.study_levels sl on sl.code=s.level_code left join ref.fields_of_study fos on fos.name=s.field_name
on conflict(id) do nothing;

insert into workflow.migration_entity_map(migration_run_id,entity_type,source_id,source_stable_key,target_entity_id,target_stable_key,action,status)
select '11111111-1111-4111-8111-111111111111',er.entity_type,er.id::text,er.stable_key,er.id,er.stable_key,'seed','completed'
from pim.entity_registry er where er.stable_key like '%:demo:%'
on conflict do nothing;
