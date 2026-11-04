\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub',md5('admin')::uuid::text,false);
-- Like normal catalogue fixtures, this course must already have its consumer search document;
-- the real intake apply/refresh will populate its values during execution.
insert into search.course_documents(course_id,country_code) values('00000000-0000-0000-0000-000000000021','AU') on conflict do nothing;
-- Match the standard course/intake fixture's already-approved source; NULL sources must remain unpublished.
update catalogue.course_intakes set source_id=md5('sweep')::uuid where course_id='00000000-0000-0000-0000-000000000021';
-- A genuine supported value beyond the first five rows: the old synchronous probe misses it.
update pipeline.coverage_course_pages set candidates=jsonb_set(candidates,'{intake_context}','["Semester 1"]')
where course_id='00000000-0000-0000-0000-000000000021';
do $$ begin if exists(select 1 from jsonb_array_elements(security.intake_ui_selection_v1('top-au',20)->'courses') x where x->>'course_id'='00000000-0000-0000-0000-000000000021') then raise exception 'late-row reproducer is not beyond old work cap';end if;end $$;
-- The original two-argument reader delegates to the one cursor-aware implementation, with identical rows.
do $$ begin
 if exists((select to_jsonb(p) from security.intake_dates_plan_v2(null,200) p except select to_jsonb(p) from security.intake_dates_plan_v2(null,200,null,null) p)
 union all (select to_jsonb(p) from security.intake_dates_plan_v2(null,200,null,null) p except select to_jsonb(p) from security.intake_dates_plan_v2(null,200) p)) then raise exception 'canonical compatibility changed';end if;
end $$;
-- Replay and foreign ownership checks without dispatching a job.
create table public.fixture_paged_preview(k text primary key,v jsonb);
do $$ declare p jsonb;q jsonb; begin
 p:=public.admin_intake_preview_v1('start','{"scope":"top-au","size":20}');
 insert into public.fixture_paged_preview values('session',p);
 q:=public.admin_intake_preview_v1('step',jsonb_build_object('session_id',p->>'session_id','page_no',p->'page_no'));
 p:=public.admin_intake_preview_v1('step',jsonb_build_object('session_id',p->>'session_id','page_no',p->'page_no'));
 if p->'page_no' is distinct from q->'page_no' then raise exception 'replayed page advanced twice';end if;
 perform set_config('request.jwt.claim.sub',md5('other admin')::uuid::text,true);
 begin perform public.admin_intake_preview_v1('read',jsonb_build_object('session_id',p->>'session_id')); raise exception 'foreign preview accepted'; exception when insufficient_privilege then null;end;
 raise notice 'PASS canonical compatibility, idempotent page replay and foreign preview denial';
end $$;
-- Keyset pages must equal the canonical uninterrupted reader, including ordering/ties.
do $$ declare ids uuid[];a jsonb;b jsonb;allrows jsonb;begin
 ids:=array(select id from catalogue.courses where id::text like '00000000-%' order by id limit 20);
 select jsonb_agg(to_jsonb(p) order by p.course_id,p.intake_id) into a from security.intake_dates_plan_v2(ids,5,null,null) p;
 select jsonb_agg(to_jsonb(p) order by p.course_id,p.intake_id) into b from security.intake_dates_plan_v2(ids,5,(a->-1->>'course_id')::uuid,(a->-1->>'intake_id')::uuid) p;
 select jsonb_agg(to_jsonb(p) order by p.course_id,p.intake_id) into allrows from security.intake_dates_plan_v2(ids,10) p;
 if jsonb_array_length(a)<>5 or jsonb_array_length(b)<>5 or a||b is distinct from allrows then raise exception 'keyset pages differ from canonical reader';end if;
 raise notice 'PASS adjacent cursor pages equal uninterrupted canonical plan';
end $$;
