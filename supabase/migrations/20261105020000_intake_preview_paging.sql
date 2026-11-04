-- Complete bounded intake discovery after #876: read the governed budget in resumable requests.
-- Replaces: security.intake_dates_plan_v2(uuid[],integer) with a compatibility delegate to its SINGLE cursor-aware body.
-- Retires: nothing. No second reader/scheduler, admission rule, consumer API or spending control change.
-- Preview sessions store read snapshots/audit only; preview NEVER writes catalogue/admission/publication values.
do $core$
declare sig text:='security.intake_dates_plan_v2(uuid[],integer)';d text:=pg_get_functiondef(sig::regprocedure);res text:=pg_get_function_result(sig::regprocedure);
 needle text:='     order by i.course_id, i.id';
begin
 if to_regprocedure('security.intake_dates_plan_v2(uuid[],integer,uuid,uuid)') is not null then
 if position('security.intake_dates_plan_v2($1,$2,null::uuid,null::uuid)' in d)=0 then raise exception 'canonical wrapper changed; reconcile';end if;
 return;end if;
 if md5(d)<>'8e3e11c3b78e4e52ea0709e48a666ff6' then raise exception 'canonical intake plan changed; Integration Controller must reconcile';end if;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'expected single canonical candidate order';end if;
 d:=regexp_replace(d,'^CREATE OR REPLACE FUNCTION security.intake_dates_plan_v2\([^\n]*\)',
 'CREATE OR REPLACE FUNCTION security.intake_dates_plan_v2(p_course_ids uuid[], p_limit integer, p_after_course uuid, p_after_intake uuid)');
 d:=replace(d,needle,'       and (p_after_course is null or (i.course_id,i.id)>(p_after_course,p_after_intake))'||chr(10)||needle);
 execute d;
 execute format('create or replace function security.intake_dates_plan_v2(p_course_ids uuid[] default null,p_limit integer default null) returns %s language sql stable security definer set search_path to '''' as $body$ select * from security.intake_dates_plan_v2($1,$2,null::uuid,null::uuid) $body$',res);
end $core$;
revoke all on function security.intake_dates_plan_v2(uuid[],integer,uuid,uuid) from public,anon,authenticated;
revoke all on function security.intake_dates_plan_v2(uuid[],integer) from public,anon,authenticated;

create table if not exists pipeline.intake_preview_sessions(
 id uuid primary key default gen_random_uuid(),requested_by uuid not null,scope text not null,size integer not null,
 universities jsonb not null,quota integer not null,page_no integer not null default 0,last_university integer not null default -1,
 state text not null default 'scanning' check(state in('scanning','ready')),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),expires_at timestamptz not null);
comment on table pipeline.intake_preview_sessions is 'Owned resumable read-only-source intake preview snapshots. No job dispatch or catalogue writes. Expiry uses existing run_now.preview_seconds.';
create table if not exists pipeline.intake_preview_rows(
 session_id uuid not null references pipeline.intake_preview_sessions(id),intake_id uuid not null,course_id uuid not null,provider_id uuid not null,
 plan jsonb not null,read_at timestamptz not null default now(),primary key(session_id,intake_id));
comment on table pipeline.intake_preview_rows is 'Canonical intake plan rows read in bounded pages, including source/evidence/eligibility stops. Private read snapshot, never consumer data.';
alter table pipeline.intake_preview_sessions enable row level security;
alter table pipeline.intake_preview_rows enable row level security;
revoke all on pipeline.intake_preview_sessions,pipeline.intake_preview_rows from public,anon,authenticated;

create or replace function security.intake_preview_result_v1(p_session uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare s pipeline.intake_preview_sessions%rowtype;r jsonb;
begin
 select * into strict s from pipeline.intake_preview_sessions where id=p_session;
 with plan as materialized(select x.plan p,x.course_id,x.provider_id from pipeline.intake_preview_rows x where x.session_id=s.id),
 f as(select * from plan where p->>'outcome'='filled' and (s.scope='top-au' or provider_id::text=s.scope)),
 c as(select course_id,min(provider_id::text)::uuid provider_id,
 array_remove(array[case when bool_or(p->>'new_year' is not null) then 'year' end,case when bool_or(p->>'new_start' is not null) then 'start_date' end,case when bool_or(p->>'new_deadline' is not null) then 'application_deadline' end],null) fills,
 string_agg(distinct coalesce(p->>'start_precision','-')||'/'||coalesce(p->>'deadline_kind','-'),'+' order by coalesce(p->>'start_precision','-')||'/'||coalesce(p->>'deadline_kind','-')) pattern,
 jsonb_agg(jsonb_build_object('intake_id',p->'intake_id','proposal_id',p->'proposal_id','calendar_evidence_id',p->'calendar_evidence_id','calendar_url',p->'calendar_url','periods',p->'periods',
 'page_url',(select e.source_url from catalogue.course_intakes i join pipeline.evidence_artifacts e on e.id=i.evidence_id where i.id=(p->>'intake_id')::uuid),'page_quote',p->'page_quote','start_quote',p->'start_quote','deadline_quote',p->'deadline_quote','deadline_kind',p->'deadline_kind','before',p->'before_value',
 'planned',jsonb_build_object('year',p->'new_year','start_date',p->'new_start','application_deadline',p->'new_deadline'),'rule',p->'rule') order by p->>'intake_id') evidence
 from f group by course_id),
 ranked as(select c.*,row_number() over(partition by provider_id order by cardinality(fills) desc,md5(course_id::text)) rp,
 row_number() over(partition by pattern order by cardinality(fills) desc,md5(course_id::text)) rq from c),
 picked as(select ranked.*,row_number() over(order by rp,rq,cardinality(fills) desc,md5(course_id::text)) n from ranked)
 select jsonb_build_object('session_id',s.id,'page_no',s.page_no,'scan_complete',s.state='ready','token',case when s.state='ready' then 'page:'||s.id end,
 'scope',s.scope,'size',s.size,'as_at',s.updated_at,'expires_at',s.expires_at,'rule','Canonical intake plan; complete independent per-university scan to governed quota or candidate end; most fields gained then round-robin providers/patterns',
 'rows_planned',(select count(*) from plan),'eligible_courses',(select count(distinct course_id) from f),
 'universities',(select jsonb_agg(u||jsonb_build_object('scan_limit',s.quota,'rows_planned',(select count(*) from plan where provider_id=(u->>'id')::uuid),
 'eligible_courses',(select count(distinct course_id) from plan where provider_id=(u->>'id')::uuid and p->>'outcome'='filled'),
 'calendar_start_rows',(select count(*) from security.calendar_dated_periods_v1((u->>'id')::uuid) where kind='start'),
 'calendar_exact_starts',(select count(*) from security.calendar_dated_periods_v1((u->>'id')::uuid) where kind='start' and on_date is not null)) order by (u->>'active_courses')::int desc,md5(u->>'id')) from jsonb_array_elements(s.universities) u),
 'skipped_by_reason',(select coalesce(jsonb_object_agg(reason,n),'{}') from(select coalesce(p->>'reason',p->>'outcome') reason,count(*) n from plan where p->>'outcome'<>'filled' and (s.scope='top-au' or provider_id::text=s.scope) group by 1) x),
 'blocked_courses',coalesce((select jsonb_agg(jsonb_build_object('course_id',b.course_id,'course_title',coalesce(c.display_title,c.canonical_title),
 'provider_name',coalesce(pr.display_name,pr.canonical_name),'stops',b.stops) order by b.course_id)
 from(select course_id,provider_id,jsonb_agg(jsonb_build_object('intake_id',p->'intake_id','reason',coalesce(p->>'reason',p->>'outcome'),
 'page_url',(select e.source_url from catalogue.course_intakes i join pipeline.evidence_artifacts e on e.id=i.evidence_id where i.id=(p->>'intake_id')::uuid))) stops
 from plan where p->>'outcome'<>'filled' and (s.scope='top-au' or provider_id::text=s.scope) group by course_id,provider_id) b
 join catalogue.courses c on c.id=b.course_id join catalogue.providers pr on pr.id=b.provider_id),'[]'),
 'courses',coalesce((select jsonb_agg(jsonb_build_object('course_id',p.course_id,'provider_id',p.provider_id,'pick',p.n,'pattern',p.pattern,'fills',p.fills,
 'course_title',coalesce(c.display_title,c.canonical_title),'provider_name',coalesce(pr.display_name,pr.canonical_name),'course_url',c.course_url,
 'eligibility_reason','The canonical plan found source-supported missing values. Missing exact calendar dates or unproved course-period wording remain blocked.',
 'at_selection',p.evidence) order by p.n) from picked p join catalogue.courses c on c.id=p.course_id join catalogue.providers pr on pr.id=p.provider_id where p.n<=s.size),'[]')) into r;
 return r;
end $$;
revoke all on function security.intake_preview_result_v1(uuid) from public,anon,authenticated;

create or replace function public.admin_intake_preview_v1(p_action text,p_args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path to '' as $$
declare s pipeline.intake_preview_sessions%rowtype;u jsonb;us jsonb;idx integer;n integer;lim integer;items jsonb;ids uuid[];scope text;sz integer;
begin
 if auth.uid() is null or coalesce(security.current_role_rank(),0)<3 then raise exception 'Operations read permission required' using errcode='42501';end if;
 if p_action='start' then
 scope:=p_args->>'scope';sz:=(p_args->>'size')::int;us:=security.intake_ui_scopes_v1();
 if scope is null or not(scope='top-au' or exists(select 1 from jsonb_array_elements(us) x where x->>'id'=scope)) then raise exception 'invalid approved university scope';end if;
 if sz is null or sz<1 or sz>security.pipeline_num_v1('run_now.pilot_cap',20)::int then raise exception 'invalid bounded cohort size';end if;
 select jsonb_agg(x||jsonb_build_object('done',false,'rows',0)) into us from jsonb_array_elements(us) x;
 insert into pipeline.intake_preview_sessions(requested_by,scope,size,universities,quota,expires_at)
 values(auth.uid(),scope,sz,coalesce(us,'[]'),greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int/greatest(jsonb_array_length(coalesce(us,'[]')),1)),
 now()+make_interval(secs=>security.pipeline_num_v1('run_now.preview_seconds',600)::int)) returning * into s;
 elsif p_action in('step','read') then
 select * into s from pipeline.intake_preview_sessions where id=(p_args->>'session_id')::uuid and requested_by=auth.uid() for update;
 if not found then raise exception 'preview is unavailable to this operator' using errcode='42501';end if;
 else raise exception 'unknown preview action';end if;
 if clock_timestamp()>s.expires_at then raise exception 'preview expired; start a fresh preview';end if;
 if s.quota<>greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int/greatest(jsonb_array_length(s.universities),1)) then raise exception 'scan budget changed; start a fresh preview';end if;
 if p_action='step' and s.state='scanning' and coalesce((p_args->>'page_no')::int,s.page_no)=s.page_no then
 select x.value,(x.ordinality-1)::int into u,idx from jsonb_array_elements(s.universities) with ordinality x
 where not(x.value->>'done')::boolean order by case when x.ordinality-1>s.last_university then 0 else 1 end,x.ordinality limit 1;
 if u is null then update pipeline.intake_preview_sessions set state='ready',updated_at=clock_timestamp() where id=s.id returning * into s;
 else
 lim:=least(greatest(1,security.pipeline_num_v1('run_now.preview_rows_per_university',5)::int),s.quota-(u->>'rows')::int);
 ids:=array(select c.id from catalogue.courses c where c.provider_id=(u->>'id')::uuid and c.lifecycle_status='active');
 select coalesce(jsonb_agg(to_jsonb(p) order by p.course_id,p.intake_id),'[]') into items
 from security.intake_dates_plan_v2(ids,lim,(u->>'after_course')::uuid,(u->>'after_intake')::uuid) p;
 n:=jsonb_array_length(items);
 insert into pipeline.intake_preview_rows(session_id,intake_id,course_id,provider_id,plan)
 select s.id,(x->>'intake_id')::uuid,(x->>'course_id')::uuid,(x->>'provider_id')::uuid,x from jsonb_array_elements(items) x on conflict do nothing;
 u:=u||jsonb_build_object('rows',(u->>'rows')::int+n,'done',n<lim or (u->>'rows')::int+n>=s.quota);
 if n>0 then u:=u||jsonb_build_object('after_course',items->-1->>'course_id','after_intake',items->-1->>'intake_id');end if;
 us:=jsonb_set(s.universities,array[idx::text],u);
 update pipeline.intake_preview_sessions set universities=us,page_no=page_no+1,last_university=idx,updated_at=clock_timestamp(),
 state=case when not exists(select 1 from jsonb_array_elements(us) x where not(x->>'done')::boolean) then 'ready' else 'scanning' end where id=s.id returning * into s;
 end if;
 end if;
 if s.state='ready' or p_action='read' then return security.intake_preview_result_v1(s.id);end if;
 return jsonb_build_object('session_id',s.id,'page_no',s.page_no,'scan_complete',false,'rows_planned',(select count(*) from pipeline.intake_preview_rows where session_id=s.id),
 'universities_done',(select count(*) from jsonb_array_elements(s.universities) x where (x->>'done')::boolean),'universities_total',jsonb_array_length(s.universities));
end $$;
revoke all on function public.admin_intake_preview_v1(text,jsonb) from public,anon;
grant execute on function public.admin_intake_preview_v1(text,jsonb) to authenticated;

create or replace function public.admin_intake_preview_prepare_v1(p_session_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare s pipeline.intake_preview_sessions%rowtype;r jsonb;req pipeline.intake_ui_requests%rowtype;ids uuid[];current_plan jsonb;c uuid;
begin
 if auth.uid() is null or coalesce(security.current_role_rank(),0)<coalesce((select control_rank from pipeline.automation_catalogue where jobname='intake-dates-apply'),6) then raise exception 'your role cannot fix this job cohort' using errcode='42501';end if;
 if coalesce(btrim(p_reason),'')='' then raise exception 'an audited reason is required';end if;
 select * into s from pipeline.intake_preview_sessions where id=p_session_id and requested_by=auth.uid() for update;
 if not found then raise exception 'preview unavailable to this operator' using errcode='42501';end if;
 select * into req from pipeline.intake_ui_requests where preview_token='page:'||s.id;
 if found then
 if req.reason<>btrim(p_reason) then raise exception 'fixed reason cannot change';end if;
 return jsonb_build_object('cohort_id',req.cohort_id,'request_key',req.request_key,'preview_token',req.preview_token,'reason',req.reason);end if;
 if s.state<>'ready' or clock_timestamp()>s.expires_at then raise exception 'complete a fresh preview before fixing a cohort';end if;
 if s.size>security.pipeline_num_v1('run_now.pilot_cap',20)::int then raise exception 'cohort cap changed; preview again';end if;
 if s.quota<>greatest(1,security.pipeline_num_v1('run_now.cohort_scan_rows',1500)::int/greatest(jsonb_array_length(s.universities),1)) then raise exception 'scan budget changed; preview again';end if;
 r:=security.intake_preview_result_v1(s.id);
 if jsonb_array_length(r->'courses')=0 then raise exception 'no source-supported eligible courses in the completed bounded scan';end if;
 ids:=array(select (x->>'course_id')::uuid from jsonb_array_elements(r->'courses') x);
 if exists(select 1 from jsonb_array_elements(r->'courses') x where not exists(select 1 from jsonb_array_elements(security.intake_ui_scopes_v1()) u where u->>'id'=x->>'provider_id')) then raise exception 'approved university scope changed; preview again';end if;
 select coalesce(jsonb_agg(to_jsonb(p)),'[]') into current_plan from security.intake_dates_plan_v2(ids,security.pipeline_num_v1('batch.intake_dates_apply',200)::int) p;
 if exists(select 1 from pipeline.intake_preview_rows old where old.session_id=s.id and old.course_id=any(ids) and old.plan->>'outcome'='filled'
 and not exists(select 1 from jsonb_array_elements(current_plan) p where p=old.plan))
 or exists(select 1 from jsonb_array_elements(current_plan) p where p->>'outcome'='filled' and not exists(select 1 from pipeline.intake_preview_rows old where old.session_id=s.id and old.plan=p)) then
 raise exception 'selected source evidence or intake values changed; preview again';end if;
 insert into pipeline.run_now_cohorts(job,label,selection_rule,selection,requested_by,reason)
 values('intake-dates-apply','Operator intake cohort',r->>'rule',r-'courses'-'token',auth.uid(),btrim(p_reason)) returning id into c;
 insert into pipeline.run_now_cohort_members(cohort_id,course_id,provider_id,pick,pattern,fills,evidence)
 select c,(x->>'course_id')::uuid,(x->>'provider_id')::uuid,(x->>'pick')::int,x->>'pattern',array(select jsonb_array_elements_text(x->'fills')),x->'at_selection' from jsonb_array_elements(r->'courses') x;
 insert into pipeline.intake_ui_requests(cohort_id,requested_by,preview_token,scope,size,reason)
 values(c,auth.uid(),'page:'||s.id,s.scope,s.size,btrim(p_reason)) returning * into req;
 insert into pipeline.admin_control_events(area,action,target,detail,actor) values('run_now','cohort_prepared','intake-dates-apply',jsonb_build_object('cohort_id',c,'preview_session',s.id),auth.uid());
 return jsonb_build_object('cohort_id',c,'request_key',req.request_key,'preview_token',req.preview_token,'reason',req.reason);
end $$;
revoke all on function public.admin_intake_preview_prepare_v1(uuid,text) from public,anon;
grant execute on function public.admin_intake_preview_prepare_v1(uuid,text) to authenticated;

do $caps$ declare d text:=pg_get_functiondef('public.admin_intake_run_read_v1(text,jsonb)'::regprocedure);
begin
 if position('''paged_preview'',true' in d)>0 then return;end if;
 if md5(d)<>'fa7d47a39f1401e54e751fbfe4de29c9' then raise exception 'intake read bridge changed; reconcile';end if;
 if (length(d)-length(replace(d,'''contract'',''intake-run-validate-v1''','')))/length('''contract'',''intake-run-validate-v1''')<>1 then raise exception 'capability contract changed; reconcile';end if;
 execute replace(d,'''contract'',''intake-run-validate-v1''','''contract'',''intake-run-validate-v1'',''paged_preview'',true');
end $caps$;
update pipeline.platform_toolset_settings set label='Run now: preview rows per request',help='Rows read per resumable preview request. The full existing run_now.cohort_scan_rows budget is evaluated independently across universities before a cohort can be fixed. Lower this per-request value if a page times out; the full scan coverage is preserved.',used_by='security.intake_ui_selection_v1; public.admin_intake_preview_v1',reason='Complete bounded discovery without truncating at the per-request work limit' where toolset_key='pipeline' and key='run_now.preview_rows_per_university';
update pipeline.platform_toolset_settings set used_by=used_by||'; public.admin_intake_preview_v1; public.admin_intake_preview_prepare_v1' where toolset_key='pipeline' and key='run_now.preview_seconds' and position('public.admin_intake_preview_v1' in coalesce(used_by,''))=0;
insert into pipeline.component_register(kind,name,layer,area,purpose,status,replaces,introduced_in)
select kind,name,'Layer 2','Admission','Resumable governed intake preview: '||name,'active','{}','20261105020000' from(values
 ('table','pipeline.intake_preview_sessions'),('table','pipeline.intake_preview_rows'),('function','security.intake_dates_plan_v2(uuid[],integer,uuid,uuid)'),
 ('function','security.intake_preview_result_v1'),('function','public.admin_intake_preview_v1'),('function','public.admin_intake_preview_prepare_v1')) x(kind,name) on conflict do nothing;
