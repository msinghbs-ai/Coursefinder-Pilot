-- Guards: Provider Description autonomy mandate §8–11: actual production constraints, permissions, source validation, human admission.
set jit=off; set work_mem='7168kB'; set max_parallel_workers_per_gather=1; set statement_timeout='8s'; set lock_timeout='0';
create function fixture.refuses(stmt text,expected text,reason text) returns void language plpgsql as $$
begin
 begin execute stmt;
 exception when others then
  if sqlstate=expected then raise notice 'PASS % (SQLSTATE %)',reason,sqlstate; return; end if;
  raise exception 'FAIL % expected SQLSTATE %, got %: %',reason,expected,sqlstate,sqlerrm;
 end;
 raise exception 'FAIL % was accepted',reason;
end$$;
select fixture.ok((select version() like 'PostgreSQL 17.6%'),'PostgreSQL 17.6 production engine family');
select fixture.ok((select count(*) from pg_constraint where conrelid='pipeline.admin_jobs'::regclass and conname='admin_jobs_outcome_fkey')=1,'actual outcome reference FK installed');
select fixture.refuses($q$insert into pipeline.admin_jobs(kind,title,requested_by,reason,outcome) values('job_run_now','invalid','90000000-0000-0000-0000-0000000000aa','negative acceptance','ran')$q$,'23503','old Run Now ran value refused by actual production FK');
select fixture.refuses($q$insert into pipeline.admin_jobs(kind,title,requested_by,reason,outcome) values('job_run_now','invalid','90000000-0000-0000-0000-0000000000aa','negative acceptance','refused')$q$,'23503','old Run Now refused value refused by actual production FK');
select fixture.refuses($q$insert into pipeline.admin_jobs(kind,title,requested_by,reason,outcome) values('job_run_now','invalid','90000000-0000-0000-0000-0000000000aa','negative acceptance','invented')$q$,'23503','invented outcome refused by actual production FK');
select fixture.refuses($q$insert into pipeline.admin_jobs(kind,title,requested_by,reason) values('invented','invalid','90000000-0000-0000-0000-0000000000aa','negative acceptance')$q$,'23503','unsupported governed job kind refused');
select fixture.refuses($q$insert into pipeline.admin_jobs(kind,state,title,requested_by,reason) values('job_run_now','approved','invalid','90000000-0000-0000-0000-0000000000aa','negative acceptance')$q$,'23514','unsupported job state refused');
select fixture.refuses($q$insert into pipeline.provider_description_reads(provider_id,state) values('10000000-0000-0000-0000-000000000001','auto_approved')$q$,'23514','unsupported description admission state refused');
select fixture.refuses($q$insert into pipeline.provider_description_reads(provider_id) values('ffffffff-ffff-ffff-ffff-ffffffffffff')$q$,'23503','description provider FK refused unrelated identity');
select fixture.refuses($q$insert into pipeline.layer4_review_items(entity_type,entity_id,field_code,status) values('provider','10000000-0000-0000-0000-000000000001','provider_description','auto_approved')$q$,'23514','unsupported Layer 4 approval state refused');
select fixture.ok(not security.provider_description_scope_v1('10000000-0000-0000-0000-000000000016'),'retired provider excluded by actual scope');
select fixture.ok(not security.provider_description_scope_v1('10000000-0000-0000-0000-000000000018'),'university versus college governed type boundary');
select fixture.ok(security.provider_description_stored_v1('10000000-0000-0000-0000-000000000014') is null,'no official source does not invent evidence');
select fixture.ok((security.provider_description_page_v1('10000000-0000-0000-0000-000000000001','https://p2.example.edu/about')->>'ok')='false','similarly named provider cannot borrow another official host');
select fixture.ok((security.provider_description_page_v1('10000000-0000-0000-0000-000000000001','https://p1.example.edu/news/about-research')->>'ok')='false','news and research paths cannot masquerade as About page');
-- Real manual lock trigger, independent of reader controls.
update catalogue.providers set description='An automated write attempted to replace the manual description.' where id='10000000-0000-0000-0000-000000000017';
select fixture.ok((select description='This existing manual description must remain exactly as entered by the operator.' from catalogue.providers where id='10000000-0000-0000-0000-000000000017'),'actual production manual lock trigger prevents replacement');
-- Actual evidence version trigger, not an idealised schema without lineage enforcement.
insert into pipeline.layer2_source_profile_versions(id) values('20000000-0000-0000-0000-000000000001'),('20000000-0000-0000-0000-000000000002');
insert into pipeline.jobs(id,source_profile_version_id) values('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
select fixture.refuses($q$insert into pipeline.evidence_artifacts(evidence_type,job_id,source_profile_version_id) values('page','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002')$q$,'23514','actual source configuration evidence version mismatch refused');
