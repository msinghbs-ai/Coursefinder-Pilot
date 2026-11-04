\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub',md5('admin')::uuid::text,false);
do $$
declare p jsonb; f jsonb; r jsonb; s text; id uuid;
begin
 -- Read-only preview makes no cohort or request row.
 select count(*)::text into s from pipeline.intake_ui_requests;
 p:=public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":1}');
 perform pg_temp.ok((select count(*)::text from pipeline.intake_ui_requests)=s,'preview is read-only');
 begin perform public.admin_intake_cohort_prepare_v1('top-au',1,'bad',(jsonb_set((p->>'token')::jsonb,'{body,size}','2'))::text); raise exception 'FAIL signed size tamper accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',md5('other admin')::uuid::text,true);
 begin perform public.admin_intake_cohort_prepare_v1('top-au',1,'bad',p->>'token'); raise exception 'FAIL cross-user preview accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 -- Publication match checks all non-null values, not only a start date or year.
 perform pg_temp.ok(security.intake_ui_values_match_v1('{"year":2027,"start_date":"2027-03-01","application_deadline":"2026-11-30"}',
 '[{"year":2027,"start_date":"2027-03-01","application_deadline":"2026-11-30"}]'),'all consumer fields match');
 perform pg_temp.ok(not security.intake_ui_values_match_v1('{"year":2027,"application_deadline":"2026-11-30"}',
 '[{"year":2027,"application_deadline":"2026-12-01"}]'),'deadline mismatch cannot pass publication');
 perform pg_temp.ok(security.intake_ui_values_match_v1('{"year":2027}','{"error":"unsupported"}') is null,'unsupported is unknown, not true');
 f:=(select v from public.fixture_intake_ui where k='fixed'); id:=(f->>'cohort_id')::uuid;
 r:=public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',id));
 perform pg_temp.ok((select bool_and(x->'publication'->>'website'='verified' and x->'publication'->>'catalogue'='verified' and x->'publication'->>'zoho'='unsupported') from jsonb_array_elements(r->'courses') x),'full read-back scalar verification');
 raise notice 'PASS read-only preview, signed token tamper, cross-user preview, complete consumer match, deadline mismatch and unsupported status';
end $$;
-- Additional real plan/token cases using a new eligible controlled course.
select pg_temp.course('ui stale','harbour','harbour.edu.au','UI105','Master of Preview Integrity','Semester 1');
select pg_temp.intake('ui stale','March');
do $$
declare p jsonb; tok jsonb; body jsonb; sig text; old jsonb; scope text;
begin
 select id::text into scope from catalogue.providers where id=md5('harbour')::uuid;
 p:=public.admin_intake_run_read_v1('preview',jsonb_build_object('scope',scope,'size',1));
 perform pg_temp.ok((select bool_and(x->>'provider_id'=scope) from jsonb_array_elements(p->'courses') x),'individual university scope is genuinely bounded');
 select candidates into old from pipeline.coverage_course_pages where course_id=md5('ui stale')::uuid;
 update pipeline.coverage_course_pages set candidates=jsonb_set(candidates,'{intake_context}','["March only"]') where course_id=md5('ui stale')::uuid;
 begin perform public.admin_intake_cohort_prepare_v1(scope,1,'stale',p->>'token'); raise exception 'FAIL stale evidence accepted';
 exception when others then if sqlerrm not like 'selection or evidence changed%' then raise; end if; end;
 update pipeline.coverage_course_pages set candidates=old where course_id=md5('ui stale')::uuid;
 tok:=(p->>'token')::jsonb; body:=jsonb_set(tok->'body','{expires_at}',to_jsonb(now()-interval '1 second'));
 select encode(extensions.hmac(body::text,secret,'sha256'),'hex') into sig from pipeline.intake_ui_signing_key;
 tok:=jsonb_build_object('body',body,'signature',sig);
 begin perform public.admin_intake_cohort_prepare_v1(scope,1,'expired',tok::text); raise exception 'FAIL expired accepted';
 exception when others then if sqlerrm not like 'preview expired%' then raise; end if; end;
 insert into pipeline.manual_locks values('course',md5('ui stale')::uuid,'intakes');
 raise notice 'PASS narrowed university scope, changed source evidence and expired signed preview';
end $$;
-- Supported Zoho transport fixture: contract exercise only, not independent production-publication proof.
create or replace function public.zoho_edge_course_lookup_v1(p_identifier text) returns jsonb language sql as $$
 select api.website_v2_course_item(p_identifier::uuid) $$;
do $$
declare r jsonb; id uuid:=(select (v->>'cohort_id')::uuid from public.fixture_intake_ui where k='fixed');
begin
 r:=public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',id));
 perform pg_temp.ok((select bool_and(x->'publication'->>'zoho'='verified') from jsonb_array_elements(r->'courses') x),'supported Zoho shape compared across all admitted scalars');
 raise notice 'PASS supported Zoho bridge fixture (not production proof)';
end $$;
create or replace function public.zoho_edge_course_lookup_v1(p_identifier text) returns jsonb language plpgsql as $$ begin raise exception 'fixture: Zoho not connected'; end $$;
-- Offline equivalent of the relevant security advisor checks for the NEW objects.
do $$ begin
 perform pg_temp.ok(not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='pipeline' and c.relname in('intake_ui_requests','intake_ui_signing_key') and not c.relrowsecurity),'new private tables have RLS');
 perform pg_temp.ok(not has_table_privilege('authenticated','pipeline.intake_ui_requests','SELECT') and not has_table_privilege('authenticated','pipeline.intake_ui_signing_key','SELECT'),'no private table grants');
 perform pg_temp.ok(not has_function_privilege('authenticated','security.intake_ui_selection_v1(text,integer)','EXECUTE') and not has_function_privilege('anon','public.admin_intake_run_read_v1(text,jsonb)','EXECUTE'),'no private function or anonymous bridge execution');
 raise notice 'PASS new-object RLS, table and function privilege checks';
end $$;
