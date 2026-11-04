\set ON_ERROR_STOP on
do $$ declare c uuid; r jsonb; j pipeline.admin_jobs%rowtype; n integer; begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 select cohort_id into strict c from pipeline.intake_ui_requests where reason='Browser to PostgreSQL operational acceptance';
 select * into strict j from pipeline.admin_jobs where kind='job_run_now' and args->>'cohort_id'=c::text;
 if j.state<>'done' or j.outcome<>'succeeded_with_result' or (j.result->>'admitted')::int<>20 or (j.result->>'processed')::int<>20 then raise exception 'twenty-course job outcome wrong'; end if;
 if (select count(*) from pipeline.run_now_cohort_members where cohort_id=c)<>20 then raise exception 'twenty-course fixed membership wrong'; end if;
 r:=public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',c));
 if jsonb_array_length(r->'courses')<>20 or exists(select 1 from jsonb_array_elements(r->'courses') x where x->'publication'->>'catalogue'<>'verified' or x->'publication'->>'website'<>'verified') then raise exception 'twenty-course admission/publication verification failed'; end if;
 -- Frozen intake response contract: explicit nulls are retained; dates/year/month keep their types.
 if exists(select 1 from jsonb_array_elements(r->'courses') x cross join lateral jsonb_array_elements(x->'website_intakes') w
 where not (w ?& array['label','month','year','start_date','application_deadline'])
 or jsonb_typeof(w->'label')<>'string' or jsonb_typeof(w->'month') not in('number','null') or jsonb_typeof(w->'year') not in('number','null')
 or (w->>'start_date' is not null and w->>'start_date' !~ '^\d{4}-\d{2}-\d{2}$')
 or (w->>'application_deadline' is not null and w->>'application_deadline' !~ '^\d{4}-\d{2}-\d{2}$')) then raise exception 'consumer intake response contract drift'; end if;
 if exists(select 1 from pipeline.run_now_cohort_members m join catalogue.course_intakes i on i.course_id=m.course_id
 left join pipeline.evidence_lineage_stats s on s.evidence_id=i.evidence_id
 left join pipeline.evidence_entity_links l on l.evidence_id=i.evidence_id and l.entity_id=i.course_id and l.entity_type='course'
 where m.cohort_id=c and (coalesce(s.observation_count,0)<1 or coalesce(l.link_count,0)<1)) then raise exception 'authoritative evidence triggers did not retain lineage'; end if;
 raise notice 'PASS post-browser: twenty selected/admitted/published courses, one persisted task after dropped-response recovery, typed API intake contract and authoritative evidence lineage';
end $$;
