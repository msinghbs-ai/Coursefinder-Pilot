-- Controlled official-source-shaped data only. No production courses, IDs or personal data copied.
-- Ten AU universities: three existing fixture universities plus seven generated ones.
update pipeline.platform_toolset_settings set value='20' where toolset_key='pipeline' and key='run_now.pilot_cap';
insert into catalogue.providers(id,canonical_name,website,country_id,provider_type_id)
select pg_temp.u('scale uni '||n),'Fixture Australian University '||n,'https://fixture'||n||'.edu.au',pg_temp.u('AU'),(select id from ref.provider_types where code='university') from generate_series(1,7) n;
insert into pipeline.provider_policy_proposals(id,provider_id,kind,parser,url,evidence_id,proposal,status,decided_at)
select pg_temp.u('scale cal '||n),pg_temp.u('scale uni '||n),kind,parser,'https://fixture'||n||'.edu.au/calendar',evidence_id,proposal,status,now()
from pipeline.provider_policy_proposals cross join generate_series(1,7) n where id=pg_temp.u('cal harbour');
-- Dominant university: 5,000 active courses, 2,500 low-sorting intake candidates without evidence.
-- The old global scan is consumed entirely by this provider. Every other university must still be evaluated.
insert into catalogue.courses(id,provider_id,canonical_title,lifecycle_status)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,pg_temp.u('scale uni 1'),'Dominant fixture course '||n,'active' from generate_series(1,5000) n;
insert into catalogue.course_intakes(course_id,intake_label,status)
select id,'March','active' from catalogue.courses where provider_id=pg_temp.u('scale uni 1') order by id limit 2500;
-- Real supported page/calendar wording for 24 courses across eight other universities.
do $$ declare pr text; host text; i integer; begin
 foreach pr in array array['harbour','bay','scale uni 2','scale uni 3','scale uni 4','scale uni 5','scale uni 6','scale uni 7'] loop
 host:=case when pr='harbour' then 'harbour.edu.au' when pr='bay' then 'bay.edu.au' else 'fixture'||right(pr,1)||'.edu.au' end;
 for i in 1..3 loop
 perform pg_temp.course('twenty '||pr||i,pr,host,'TW'||right(md5(pr),5)||i,'Master of Intake Acceptance '||pr||' '||i,'Semester 1');
 perform pg_temp.intake('twenty '||pr||i,'March');
 end loop; end loop;
end $$;
-- Fill every university's scan with 200 later-sorting ineligible rows, including the no-calendar provider.
-- This exercises the configured overall 1,500-row budget and preserves a genuine zero denominator for Inland.
insert into catalogue.courses(id,provider_id,canonical_title,lifecycle_status)
select ('ffffffff-0000-0000-'||lpad(u.n::text,4,'0')||'-'||lpad(i::text,12,'0'))::uuid,u.id,'No-evidence scale course '||i,'active'
from (select id,row_number() over(order by id) n from catalogue.providers) u cross join generate_series(1,200) i;
insert into catalogue.course_intakes(course_id,intake_label,status)
select id,'March','active' from catalogue.courses where id::text like 'ffffffff-%';
analyze catalogue.courses; analyze catalogue.course_intakes; analyze pipeline.provider_policy_proposals; analyze pipeline.course_intake_dates;
select set_config('request.jwt.claim.sub',md5('admin')::uuid::text,false);
set statement_timeout='8s';
do $$ declare p jsonb; total integer; begin
 p:=public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":20}');
 perform pg_temp.ok(jsonb_array_length(p->'courses')=20,'20 eligible courses automatically selected');
 perform pg_temp.ok(jsonb_array_length(p->'universities')=10,'all ten Australian universities reported');
 perform pg_temp.ok((select count(*) from jsonb_array_elements(p->'universities') u where (u->>'eligible_courses')::int=0)>=2,'zero eligibility explicitly reported');
 perform pg_temp.ok((select count(distinct x->>'provider_id') from jsonb_array_elements(p->'courses') x)=8,'eight universities contribute despite dominant scan pressure');
 select count(*) into total from security.intake_dates_plan_v2(array(select id from catalogue.courses where lifecycle_status='active'),1500) where outcome='filled';
 perform pg_temp.ok(total=0,'regression reproducer: old global scan finds zero eligible while independent scans find 20');
 raise notice 'PASS 20-course preview, all ten denominators including zero, dominant-university starvation regression under 8-second statement limit';
end $$;
reset statement_timeout;
