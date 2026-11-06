-- Guards: Provider Description autonomy §9–11. Fictional, source-shaped isolated data; no live entities/evidence.
create schema fixture;
create function fixture.ok(ok boolean,reason text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'FAIL %',reason; end if; raise notice 'PASS %',reason; end$$;
create table fixture.documents(provider_id uuid primary key,evidence_id uuid,html text,model_answer jsonb);
-- Only hosted pg_net/worker transport is controlled: persist the actual scheduler body and its completion.
create table fixture.worker_dispatches(request_id bigint primary key,function_name text,body jsonb,created_at timestamptz default now(),completed_at timestamptz);
create or replace function pipeline.svc_pilot_submit_nonce(p_function text,p_body jsonb) returns bigint language plpgsql as $f$
declare v bigint;begin
 insert into pipeline.edge_request_log(function_name,mode) values(p_function,p_body->>'mode') returning id into v;
 update pipeline.edge_request_log set request_id=v where id=v;
 insert into fixture.worker_dispatches(request_id,function_name,body) values(v,p_function,p_body);
 return v;
end $f$;
insert into ref.countries(id,iso_alpha2) values ('00000000-0000-0000-0000-0000000000a1','AU'),('00000000-0000-0000-0000-0000000000a2','NZ'),('00000000-0000-0000-0000-0000000000a3','CA');
insert into ref.provider_types(id,code,name) values ('00000000-0000-0000-0000-0000000000b1','university','University'),('00000000-0000-0000-0000-0000000000b2','college','College');
-- Isolated caller identity stands for a signed in approved operator. Actual RPC rank checks still execute.
insert into auth.users(id,email) values('90000000-0000-0000-0000-0000000000aa','isolated-operator@example.invalid') on conflict do nothing;
set fx.uid='90000000-0000-0000-0000-0000000000aa'; set fx.rank='6'; set fx.role='authenticated';
insert into cron.job(jobname,schedule,command,active) values('provider-description-read','6,16,26,56 * * * *','select security.provider_description_fire_v1()',true) on conflict(jobname) do update set active=true;
insert into pipeline.platform_toolset_settings(toolset_key,key,kind,value) values('pipeline','run_now.jobs','list','[]'),('pipeline','run_now.pilot_cap','number','20'),('pipeline','batch.provider_description','number','3') on conflict(toolset_key,key) do nothing;
update pipeline.platform_toolset_settings set value=value||'"provider-description-read"'::jsonb where toolset_key='pipeline' and key='run_now.jobs' and not value?'provider-description-read';
insert into auth.users(id,email) select ('90000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'isolated-role-'||n||'@example.invalid' from generate_series(0,5)n;
insert into security.roles(code,name,rank,status) values('fixture_viewer','Fixture Viewer',2,'active'),('fixture_curator','Fixture Curator',3,'active'),('fixture_reviewer','Fixture Reviewer',4,'active');
insert into security.user_roles(user_id,role_code) values('90000000-0000-0000-0000-000000000002','fixture_viewer'),('90000000-0000-0000-0000-000000000003','fixture_curator'),('90000000-0000-0000-0000-000000000004','fixture_reviewer'),('90000000-0000-0000-0000-000000000005','platform_admin');
-- Acquisition stays disabled throughout local acceptance. Settings below grant only fictional fixture scope, never live scope.
update pipeline.platform_toolset_settings set value='0'::jsonb where toolset_key='pipeline' and key in('pdesc.acquire_direct','pdesc.acquire_firecrawl');
update pipeline.platform_toolset_settings set value='["AU","NZ","CA"]'::jsonb where toolset_key='pipeline' and key='pdesc.countries';
update pipeline.platform_toolset_settings set value='1'::jsonb where toolset_key='pipeline' and key='pdesc.enabled';
do $$declare x record; pid uuid; eid uuid; sid uuid; cc uuid; name text; body text; sentence1 text; sentence2 text; ky text; begin
 for x in select * from (values
 (1,'Aurora Maritime','marine navigation and coastal engineering','ocean research and nautical practice',1),
 (2,'Birch Valley','forest ecology and sustainable agriculture','woodland conservation and agricultural science',1),
 (3,'Copper Ridge','mineral geology and resource surveying','mountain fieldwork and geological mapping',1),
 (4,'Dune Plains','desert botany and environmental planning','arid landscapes and ecological restoration',1),
 (5,'Elm Arts','music composition and theatre performance','creative production and dramatic interpretation',1),
 (6,'Fjord Technical','mechanical design and manufacturing systems','industrial projects and mechanical laboratories',1),
 (7,'Granite Health','nursing practice and community health','clinical learning and public healthcare',1),
 (8,'Harbour Digital','computing systems and software development','digital technology and programming practice',1),
 (9,'Inland Languages','linguistics research and language education','cross cultural communication and language study',1),
 (10,'Juniper Social','social policy and community development','public services and social research',1),
 (11,'Kiwi Lake','freshwater science and aquatic conservation','lake ecosystems and water management',2),
 (12,'Maple Snow','winter ecology and northern geography','polar landscapes and geographical research',3),
 (13,'Browser Cedar','botanical science and plant conservation','garden research and ecological education',1),
 (14,'No Source','historical study and museum curation','archival research and cultural preservation',1),
 (15,'Conflict Hill','economic analysis and business study','commerce teaching and economic research',1),
 (16,'Retired Bay','retired provider and former college','previous identity and closed programmes',1),
 (17,'Manual Stone','mathematical theory and statistical science','analytical methods and numerical research',1),
 (18,'College Crescent','vocational study and hospitality practice','culinary learning and workplace training',1)
 ) t(n,label,subjects,approach,country) loop
   pid:=('10000000-0000-0000-0000-'||lpad(x.n::text,12,'0'))::uuid;
   name:=x.label||case when x.n=18 then ' College' else ' University' end;
   ky:='fixture:provider:'||case when x.n=13 then 'browser' else x.n::text end;
   cc:=('00000000-0000-0000-0000-0000000000a'||x.country)::uuid;
   insert into pim.entity_registry(id) values(pid);
   insert into catalogue.providers(id,stable_key,canonical_name,website,country_id,provider_type_id,lifecycle_status,publication_status)
   values(pid,ky,name,'https://p'||x.n||'.example.edu',cc,case when x.n=18 then '00000000-0000-0000-0000-0000000000b2'::uuid else '00000000-0000-0000-0000-0000000000b1'::uuid end,
     case when x.n=16 then 'retired' else 'active' end,'published');
   if x.n=17 then update catalogue.providers set description='This existing manual description must remain exactly as entered by the operator.' where id=pid;
     insert into pipeline.manual_locks(entity,entity_id,field,mode) values('provider',pid,'description','value'); end if;
   -- Real consumer provider projection reads search documents. No API response is fabricated.
   if x.n<>16 then insert into search.course_documents(provider_id,provider_stable_key,provider_name,country_code,has_scholarship,study_level_code,primary_field_code,primary_field_name)
    values(pid,ky,name,case x.country when 1 then 'AU' when 2 then 'NZ' else 'CA' end,false,'bachelor','science','Science'); end if;
   insert into catalogue.courses(id,provider_id,canonical_title,lifecycle_status)
    select gen_random_uuid(),pid,'Fictional programme '||g,'active' from generate_series(1,case when x.n=1 then 7000 else 80+x.n*13 end)g;
   if x.n<>14 then
    insert into pipeline.sources(source_type,provider_id,label,url) values('provider_course_page_sweep',pid,'Stored institutional About page','https://p'||x.n||'.example.edu/about') returning id into sid;
    insert into pipeline.evidence_artifacts(source_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at)
    values(sid,'page','https://p'||x.n||'.example.edu/about','fixture/about-'||x.n||'.html',repeat(lpad(to_hex(x.n),2,'0'),32),'text/html',now()) returning id into eid;
    sentence1:=name||' offers education in '||x.subjects||'.';
    sentence2:='Its teaching and learning focus on '||x.approach||', supporting the development of knowledge in these fields.';
    body:='<html><title>About '||name||'</title><main><h1>'||case when x.n=15 then 'Conflict Hill College' else name end||'</h1><p>'||sentence1||'</p><p>'||sentence2||'</p></main></html>';
    insert into fixture.documents values(pid,eid,body,jsonb_build_object('about_page',true,'sentences',jsonb_build_array(jsonb_build_object('text',sentence1,'quote',sentence1),jsonb_build_object('text','Teaching focuses on '||x.approach||' and develops knowledge through learning in these fields.','quote',sentence2))));
   end if;
 end loop;
end$$;
insert into catalogue.provider_registrations(provider_id,registration_scheme,registration_code,provider_classification,status,checked_at,source_id,evidence_id)
select p.id,case k.iso_alpha2 when 'AU' then 'cricos' when 'NZ' then 'nzqa' else 'fixture_ca' end,'FX'||right(p.id::text,6),'Fictional test reference','active',now(),a.source_id,d.evidence_id from catalogue.providers p join ref.countries k on k.id=p.country_id left join fixture.documents d on d.provider_id=p.id left join pipeline.evidence_artifacts a on a.id=d.evidence_id;
update pipeline.platform_toolset_settings set value=(select jsonb_agg(stable_key) from catalogue.providers) where toolset_key='pipeline' and key='pdesc.provider_keys';
-- Include an unapproved, absent-country source in realistic multi-country distributions; selector must honour actual scope settings.
insert into pipeline.platform_toolsets(key,enforcement) values('openrouter','stop');
insert into pipeline.platform_toolset_settings(toolset_key,key,kind,value) values('pipeline','budgets.ai_daily_ceiling_usd','number','14') on conflict(toolset_key,key) do update set value=excluded.value;
set fx.role='service_role';
