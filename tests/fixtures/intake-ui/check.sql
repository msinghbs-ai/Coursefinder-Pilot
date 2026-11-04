\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub',md5('admin')::uuid::text,false);
create table public.fixture_intake_ui(k text primary key,v jsonb);
do $$
declare p jsonb; fixed jsonb; r jsonb; v jsonb; id uuid; n int;
begin
 p:=public.admin_intake_run_read_v1('capabilities');
 perform pg_temp.ok((p->>'can_run')::boolean and jsonb_array_length(p->'universities')>0,'real university scope/counts');
 begin perform public.admin_intake_run_read_v1('preview','{"scope":"unknown","size":1}'); raise exception 'FAIL scope accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
 p:=public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":4}');
 perform pg_temp.ok(exists(select 1 from jsonb_array_elements(p->'courses') x where x->>'course_id'=md5('ui exact')::uuid::text),'genuine eligible plan member');
 perform pg_temp.ok(not exists(select 1 from jsonb_array_elements(p->'courses') x where x->>'course_id' in(md5('ui missing')::uuid::text,md5('ui locked')::uuid::text)),'missing calendar and manual lock excluded');
 perform pg_temp.ok((select bool_and(jsonb_array_length(x->'at_selection')>0 and x->'at_selection'->0->>'page_quote'<>'') from jsonb_array_elements(p->'courses') x),'official stored source evidence retained');
 begin perform public.admin_intake_cohort_prepare_v1('top-au',4,'test',replace(p->>'token','sha256','tamper')||'x'); raise exception 'FAIL tamper accepted'; exception when others then if sqlerrm like 'FAIL%' then raise; end if; end;
 fixed:=public.admin_intake_cohort_prepare_v1('top-au',4,'integration test',p->>'token'); id:=(fixed->>'cohort_id')::uuid;
 perform pg_temp.ok(public.admin_intake_cohort_prepare_v1('top-au',4,'integration test',p->>'token')=fixed,'duplicate preparation same fixed cohort and key');
 insert into public.fixture_intake_ui values('fixed',fixed);
 perform pg_temp.ok((select count(*) from pipeline.run_now_cohort_members where cohort_id=id)=jsonb_array_length(p->'courses'),'exact fixed membership');
 r:=public.admin_intake_run_now_v1(id);
 perform pg_temp.ok(r->>'state'='done' and (r->>'admitted')::int>0 and (r->>'vendor_calls')::int=0,'existing governed job admitted; zero vendor spend');
 v:=public.admin_intake_run_now_v1(id);
 perform pg_temp.ok(v->>'run_id'=r->>'run_id' and (v->>'repeat')::boolean,'interrupted response recovery same saved run');
 v:=public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',id));
 perform pg_temp.ok((v->'totals'->>'admitted')::int>0 and (v->'totals'->>'published')::int>0 and (v->'totals'->>'not_as_planned')::int=0,'catalogue delta and real core projection Website readback');
 perform pg_temp.ok(v->'runs'->0->>'run_id'=r->>'run_id' and v->'saved_request'->>'request_key'=fixed->>'request_key','saved IDs, counts and keys restored by read RPC');
 perform pg_temp.ok((v->'totals'->>'zoho_checked')::int=0,'unavailable Zoho explicitly unsupported, not synthetic pass');
 perform pg_temp.ok((select start_date is null from catalogue.course_intakes where course_id=md5('ui locked')::uuid),'manual lock remains');
 raise notice 'PASS vertical SQL: scope/evidence, fixed integrity, governed run, admission, catalogue, Website projection, unsupported Zoho, saved/repeated request and zero spend';
end $$;
-- Actual authenticated role, rather than owner-only function tests.
set role authenticated;
select public.admin_intake_run_read_v1('capabilities')->>'contract';
select set_config('request.jwt.claim.sub',md5('reader')::uuid::text,false);
do $$ begin
 begin perform public.admin_intake_cohort_prepare_v1('top-au',1,'denied','{}'); raise exception 'FAIL reader prepared'; exception when insufficient_privilege then null; end;
 begin perform public.admin_job_run_now_v1('intake-dates-apply','denied','{}'); raise exception 'FAIL reader ran'; exception when insufficient_privilege then null; end;
 begin perform public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',(select null::uuid))); raise exception 'FAIL foreign cohort read'; exception when insufficient_privilege then null; end;
 raise notice 'PASS authenticated read role cannot prepare/run/read foreign cohort';
end $$;
select set_config('request.jwt.claim.sub','',false);
do $$ begin begin perform public.admin_intake_run_read_v1('capabilities'); raise exception 'FAIL anonymous read'; exception when insufficient_privilege then null; end; end $$;
reset role;
