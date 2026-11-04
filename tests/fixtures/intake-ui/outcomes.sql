\set ON_ERROR_STOP on
-- The real FK must reject both buggy outcome strings even when the task otherwise has valid fields.
do $$ declare bad text; begin
 foreach bad in array array['ran','refused','invented'] loop
 begin
 insert into pipeline.admin_jobs(id,kind,lane,state,title,args,requested_by,reason,outcome)
 values(gen_random_uuid(),'job_run_now','run_now','done','invalid fixture outcome','{}',md5('admin')::uuid,'invalid outcome regression',bad);
 raise exception 'FAIL invalid outcome accepted: %',bad;
 exception when foreign_key_violation then null; end;
 end loop;
 perform pg_temp.ok(exists(select 1 from pipeline.admin_jobs where outcome='succeeded_with_result'),'corrected success outcome persists under production FK');
 raise notice 'PASS invalid outcome codes rejected by production FK; corrected successful result persists';
end $$;
do $$ declare f jsonb; r jsonb; begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 f:=(select v from public.fixture_intake_ui where k='fixed');
 r:=public.admin_job_run_now_v1('intake-dates-apply','no movement rehearsal',jsonb_build_object('cohort_id',f->>'cohort_id','idempotency_key','no-movement-rehearsal'));
 perform pg_temp.ok(r->>'state'='done' and exists(select 1 from pipeline.admin_jobs j where j.id=(r->>'run_id')::uuid and j.outcome='succeeded_no_movement'),'no-movement success uses authoritative outcome code');
 raise notice 'PASS succeeded_no_movement outcome under production FK';
end $$;
-- Fixture-only fault injection tests rollback semantics; canonical guards are all still enabled.
create table public.fixture_admission_fault(enabled boolean);
create function public.fixture_admission_fail() returns trigger language plpgsql as $$ begin
 if exists(select 1 from public.fixture_admission_fault where enabled) then raise exception 'controlled transient fixture admission error'; end if; return new; end $$;
create trigger fixture_admission_fail before update on catalogue.course_intakes for each row execute function public.fixture_admission_fail();
do $$ declare p jsonb; f jsonb; r jsonb; id uuid; n integer; begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 p:=public.admin_intake_run_read_v1('preview',jsonb_build_object('scope',md5('nocal')::uuid::text,'size',20));
 perform pg_temp.ok(jsonb_array_length(p->'courses')=0,'no approved calendar produces no eligible evidence');
 begin perform public.admin_intake_cohort_prepare_v1(md5('nocal')::uuid::text,20,'no evidence',p->>'token'); raise exception 'FAIL empty cohort accepted';
 exception when others then if sqlerrm not like 'no eligible courses%' then raise; end if; end;
 p:=public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":20}');
 f:=public.admin_intake_cohort_prepare_v1('top-au',20,'paused rehearsal',p->>'token'); id:=(f->>'cohort_id')::uuid;
 update cron.job set active=false where jobname='intake-dates-apply';
 r:=public.admin_intake_run_now_v1(id);
 perform pg_temp.ok(r->>'state'='refused' and exists(select 1 from pipeline.admin_jobs j where j.id=(r->>'run_id')::uuid and j.outcome='blocked_policy'),'refused run uses production blocked_policy outcome');
 update cron.job set active=true where jobname='intake-dates-apply';
 end $$;
do $$ declare p jsonb; f jsonb; r jsonb; id uuid; begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 -- A new transaction makes a separate signed preview, without altering evidence.
 p:=public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":20}');
 f:=public.admin_intake_cohort_prepare_v1('top-au',20,'failure rehearsal',p->>'token'); id:=(f->>'cohort_id')::uuid;
 insert into public.fixture_admission_fault values(true);
 r:=public.admin_intake_run_now_v1(id);
 perform pg_temp.ok(r->>'state'='failed' and exists(select 1 from pipeline.admin_jobs j where j.id=(r->>'run_id')::uuid and j.outcome='failed_retryable'),'failed admission rolls back and is persisted as failed_retryable');
 delete from public.fixture_admission_fault;
 perform pg_temp.ok((public.admin_intake_run_read_v1('preview','{"scope":"top-au","size":20}')->>'eligible_courses')::int>=20,'failed execution leaves twenty-course source evidence eligible');
 raise notice 'PASS no eligible evidence, refused/blocked_policy, failed_retryable rollback and saved outcomes';
end $$;
