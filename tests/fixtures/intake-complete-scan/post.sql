\set ON_ERROR_STOP on
-- Guards: full governed coverage, cursor integrity, saved late-row evidence and private preview ownership.
do $$ declare s pipeline.intake_preview_sessions%rowtype;r jsonb;begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 select p.* into strict s from pipeline.intake_preview_sessions p join pipeline.intake_ui_requests q on q.preview_token='page:'||p.id
 where q.reason='Browser to PostgreSQL operational acceptance';
 if s.state<>'ready' or s.quota<>150 or jsonb_array_length(s.universities)<>10
 or exists(select 1 from jsonb_array_elements(s.universities) u where not(u->>'done')::boolean or (u->>'rows')::int>s.quota)
 or (select count(*) from pipeline.intake_preview_rows where session_id=s.id)<=50 then raise exception 'full independent scan did not complete';end if;
 if not exists(select 1 from pipeline.run_now_cohort_members m join pipeline.intake_ui_requests q on q.cohort_id=m.cohort_id
 where q.preview_token='page:'||s.id and m.course_id='00000000-0000-0000-0000-000000000021') then raise exception 'supported course beyond row five not admitted';end if;
 r:=public.admin_intake_preview_prepare_v1(s.id,'Browser to PostgreSQL operational acceptance');
 if public.admin_intake_preview_prepare_v1(s.id,'Browser to PostgreSQL operational acceptance') is distinct from r then raise exception 'duplicate preparation changed saved identity';end if;
 if (select count(*) from pipeline.intake_ui_requests where preview_token='page:'||s.id)<>1 then raise exception 'duplicate prepared request';end if;
 if (select count(*) from pipeline.intake_preview_rows where session_id=s.id)<>(select sum((u->>'rows')::int) from jsonb_array_elements(s.universities) u) then raise exception 'cursor row count mismatch';end if;
 if exists(select 1 from pipeline.run_now_cohort_members m join pipeline.intake_ui_requests q on q.cohort_id=m.cohort_id cross join lateral jsonb_array_elements(m.evidence) e where q.preview_token='page:'||s.id and (coalesce(e->>'page_url','')='' or coalesce(e->>'calendar_url','')='')) then raise exception 'fixed official source links missing';end if;
 if has_table_privilege('authenticated','pipeline.intake_preview_sessions','SELECT') or has_table_privilege('authenticated','pipeline.intake_preview_rows','INSERT')
 or has_function_privilege('authenticated','security.intake_dates_plan_v2(uuid[],integer,uuid,uuid)','EXECUTE')
 or has_function_privilege('authenticated','security.intake_preview_result_v1(uuid)','EXECUTE') then raise exception 'private preview leaked';end if;
 raise notice 'PASS complete scan: % pages, % rows, all ten universities, late eligible course, one saved request and consistent cursor counts',s.page_no,(select count(*) from pipeline.intake_preview_rows where session_id=s.id);
end $$;
do $$ declare s pipeline.intake_preview_sessions%rowtype;n uuid;begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 select p.* into strict s from pipeline.intake_preview_sessions p join pipeline.intake_ui_requests q on q.preview_token='page:'||p.id where q.reason='Browser to PostgreSQL operational acceptance';
 insert into pipeline.intake_preview_sessions(requested_by,scope,size,universities,quota,state,expires_at)
 values(auth.uid(),s.scope,s.size,s.universities,s.quota,'ready',now()+interval '5 minutes') returning id into n;
 insert into pipeline.intake_preview_rows select n,intake_id,course_id,provider_id,plan,read_at from pipeline.intake_preview_rows where session_id=s.id;
 begin perform public.admin_intake_preview_prepare_v1(n,'stale source test');raise exception 'FAIL stale snapshot accepted';exception when others then if sqlerrm not like 'selected source evidence or intake values changed%' then raise;end if;end;
 update pipeline.intake_preview_sessions set expires_at=now()-interval '1 minute' where id=n;
 begin perform public.admin_intake_preview_prepare_v1(n,'expired test');raise exception 'FAIL expired preview accepted';exception when others then if sqlerrm not like 'complete a fresh preview%' then raise;end if;end;
 begin perform public.admin_intake_preview_v1('start','{"scope":"not-approved","size":20}');raise exception 'FAIL invalid scope';exception when others then if sqlerrm<>'invalid approved university scope' then raise;end if;end;
 perform set_config('request.jwt.claim.sub',md5('reader')::uuid::text,true);
 begin perform public.admin_intake_preview_prepare_v1(n,'reader cannot fix');raise exception 'FAIL read role fixed cohort';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.admin_intake_preview_v1('start','{"scope":"top-au","size":20}');raise exception 'FAIL unauthenticated preview';exception when insufficient_privilege then null;end;
 raise notice 'PASS paged stale/expired snapshots, invalid scope, unauthorised preparation and unauthenticated preview refused';
end $$;
-- Setting changes invalidate unfinished previews rather than silently using an obsolete scan budget.
do $$ declare p jsonb;begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 p:=public.admin_intake_preview_v1('start','{"scope":"top-au","size":20}');
 begin
 update pipeline.platform_toolset_settings set value='1000' where toolset_key='pipeline' and key='run_now.cohort_scan_rows';
 begin perform public.admin_intake_preview_v1('step',jsonb_build_object('session_id',p->>'session_id','page_no',0));raise exception 'FAIL obsolete budget accepted';exception when others then if sqlerrm<>'scan budget changed; start a fresh preview' then raise;end if;end;
 raise exception 'rollback controlled setting fixture' using errcode='ZX001';
 exception when sqlstate 'ZX001' then null;end;
 raise notice 'PASS scan-budget setting drift refused; fixture setting restored transactionally';
end $$;
-- Real projection must refuse an intake whose source is not approved; restore the successful fixture afterwards.
do $$ declare c uuid:='00000000-0000-0000-0000-000000000021';r jsonb;cohort uuid;begin
 perform set_config('request.jwt.claim.sub',md5('admin')::uuid::text,true);
 select cohort_id into strict cohort from pipeline.intake_ui_requests where reason='Browser to PostgreSQL operational acceptance';
 begin
 update catalogue.course_intakes set source_id=null where course_id=c;
 perform search.refresh_course_enrichment_scoped_v1(array[c],true);
 r:=public.admin_intake_run_read_v1('verify',jsonb_build_object('cohort_id',cohort));
 if exists(select 1 from jsonb_array_elements(r->'courses') x where x->>'course_id'=c::text and x->'publication'->>'website'='verified') then raise exception 'unapproved source published';end if;
 raise exception 'rollback source-gate fixture' using errcode='ZX002';
 exception when sqlstate 'ZX002' then null;end;
 raise notice 'PASS missing source cannot publish through real projection; successful catalogue/source/consumer fixture restored';
end $$;
