insert into ref.currencies(code,name,numeric_code,minor_unit) values
('AUD','Australian Dollar','036',2),('CAD','Canadian Dollar','124',2),('EUR','Euro','978',2),('GBP','Pound Sterling','826',2),('NZD','New Zealand Dollar','554',2),('USD','US Dollar','840',2),('INR','Indian Rupee','356',2)
on conflict(code) do nothing;

insert into ref.countries(iso_alpha2,iso_alpha3,iso_numeric,name,official_name,default_currency_code,default_locale,catalogue_status,student_search_enabled,provider_ingestion_enabled,course_ingestion_enabled,scholarship_ingestion_enabled) values
('AU','AUS','036','Australia','Australia','AUD','en-AU','pilot',true,true,true,true),
('CA','CAN','124','Canada','Canada','CAD','en-CA','pilot',true,true,true,true),
('DE','DEU','276','Germany','Federal Republic of Germany','EUR','de-DE','pilot',true,true,true,true),
('GB','GBR','826','United Kingdom','United Kingdom of Great Britain and Northern Ireland','GBP','en-GB','pilot',true,true,true,true),
('IE','IRL','372','Ireland','Ireland','EUR','en-IE','pilot',true,true,true,true),
('NZ','NZL','554','New Zealand','New Zealand','NZD','en-NZ','pilot',true,true,true,true),
('US','USA','840','United States','United States of America','USD','en-US','pilot',true,true,true,true),
('IN','IND','356','India','Republic of India','INR','en-IN','seed_only',true,false,false,false)
on conflict(iso_alpha2) do update set catalogue_status=excluded.catalogue_status,student_search_enabled=excluded.student_search_enabled;

insert into ref.study_levels(code,name,sort_order) values
('foundation','Foundation',10),('certificate','Certificate',20),('diploma','Diploma',30),('bachelor','Bachelor',40),('graduate_certificate','Graduate Certificate',50),('graduate_diploma','Graduate Diploma',60),('masters','Masters',70),('doctorate','Doctorate / PhD',80)
on conflict(code) do nothing;

insert into ref.provider_types(code,name,description) values
('university','University','Degree-awarding university'),('college','College','College or specialist tertiary provider'),('tafe','TAFE / VET','Vocational education provider'),('other','Other','Other tertiary provider')
on conflict(code) do nothing;

insert into ref.english_tests(code,name) values
('IELTS','IELTS Academic'),('PTE','PTE Academic'),('TOEFL_IBT','TOEFL iBT'),('CAE','Cambridge C1 Advanced')
on conflict(code) do nothing;

insert into pim.attribute_families(code,name,entity_type,description,is_default) values
('provider_default','Provider','provider','Default provider family',true),('course_default','Course','course','Default course family',true),('scholarship_default','Scholarship','scholarship','Default scholarship family',true)
on conflict(code) do nothing;

insert into pim.attribute_groups(code,name,entity_type,description,display_order) values
('course_general','General','course','General course information',10),('course_academic','Academic','course','Academic structure and outcomes',20),('course_admissions','Admissions','course','Admissions and prerequisites',30),('course_english','English','course','English language requirements',40),('course_fees','Fees','course','Fees and funding',50),('course_intakes','Intakes','course','Intakes and dates',60),('course_campuses','Campuses','course','Campus and delivery',70),('course_scholarships','Scholarships','course','Scholarship context',80),('course_content','SEO / Content','course','Search and content enrichment',90),('course_evidence','Evidence','course','Evidence/provenance metadata',100),
('provider_general','General','provider','Provider information',10),('scholarship_general','General','scholarship','Scholarship information',10),('scholarship_eligibility','Eligibility','scholarship','Scholarship criteria',20)
on conflict(code) do nothing;

insert into pim.family_groups(family_id,group_id,display_order)
select f.id,g.id,g.display_order from pim.attribute_families f join pim.attribute_groups g on g.entity_type=f.entity_type
where f.code in ('provider_default','course_default','scholarship_default') on conflict do nothing;

insert into pim.attribute_definitions(code,name,entity_type,group_id,data_type,is_filterable,is_searchable,include_in_vector,is_bulk_editable,display_order)
select 'course_career_outcomes','Career Outcomes','course',g.id,'richtext',false,true,true,true,10 from pim.attribute_groups g where g.code='course_academic'
on conflict(code) do nothing;
insert into pim.attribute_definitions(code,name,entity_type,group_id,data_type,is_filterable,is_searchable,include_in_vector,is_bulk_editable,display_order)
select 'course_prerequisites','Prerequisites','course',g.id,'richtext',false,true,true,true,10 from pim.attribute_groups g where g.code='course_admissions'
on conflict(code) do nothing;
insert into pim.attribute_definitions(code,name,entity_type,group_id,data_type,is_filterable,is_searchable,include_in_vector,is_bulk_editable,display_order)
select 'course_keywords','Search Keywords','course',g.id,'multiselect',true,true,true,true,10 from pim.attribute_groups g where g.code='course_content'
on conflict(code) do nothing;

insert into pim.family_attributes(family_id,attribute_id,is_required,is_visible,display_order)
select f.id,a.id,false,true,a.display_order from pim.attribute_families f join pim.attribute_definitions a on a.entity_type='course' where f.code='course_default'
on conflict do nothing;

insert into search.intent_aliases(profile_id,alias,canonical_text,inferred_level_code,priority)
select p.id,v.alias,v.canonical,v.level,100 from search.profiles p cross join (values
('ai','artificial intelligence',null::text),('it','information technology',null),('cyber security','cybersecurity',null),('undergraduate','undergraduate','bachelor'),('bachelors','bachelor','bachelor'),('masters','masters','masters'),('postgraduate','postgraduate',null),('grad cert','graduate certificate','graduate_certificate'),('phd','doctorate research','doctorate'),('industry focus','industry professional applied',null),('career focus','professional applied',null)
) as v(alias,canonical,level) where p.code in ('website-default','zoho-default')
on conflict(profile_id,alias,locale) do nothing;
