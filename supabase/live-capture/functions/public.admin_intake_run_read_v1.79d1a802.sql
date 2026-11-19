CREATE OR REPLACE FUNCTION public.admin_intake_run_read_v1(p_view text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare unis jsonb; r jsonb; req pipeline.intake_ui_requests%rowtype; c uuid; rank integer:=security.current_role_rank(); blocked text;
begin
 if auth.uid() is null or rank<3 then raise exception 'Operations read permission required' using errcode='42501'; end if;
 if p_view='capabilities' then
 unis:=security.intake_ui_scopes_v1();
 blocked:=case when not exists(select 1 from pipeline.automation_catalogue where jobname='intake-dates-apply') then 'job is not catalogued'
 when not exists(select 1 from cron.job where jobname='intake-dates-apply' and active) then 'job is paused or not scheduled'
 when not coalesce((security.toolset_setting('pipeline','intake_dates.apply_enabled')#>>'{}')::boolean,false) then 'job switch is off'
 when not coalesce(security.toolset_setting('pipeline','run_now.jobs') ? 'intake-dates-apply',false) then 'job is not allowlisted' end;
 return jsonb_build_object('contract','intake-run-validate-v1','actor_id',auth.uid(),'can_run',rank>=coalesce((select control_rank from pipeline.automation_catalogue where jobname='intake-dates-apply'),6) and blocked is null,
 'control_rank',coalesce((select control_rank from pipeline.automation_catalogue where jobname='intake-dates-apply'),6),'min_size',1,
 'max_size',security.pipeline_num_v1('run_now.pilot_cap',20),'default_size',security.pipeline_num_v1('run_now.pilot_cap',20),
 'blocked_reason',blocked,'next_action',case when blocked is not null then 'An authorised operator must resolve the existing job controls; preview and saved verification remain read-only.' end,
 'scopes',jsonb_build_array(jsonb_build_object('id','top-au','label','Top '||security.pipeline_num_v1('run_now.cohort_top_au_universities',10)::int||' Australian universities by active courses'))||
 coalesce((select jsonb_agg(jsonb_build_object('id',u->>'id','label',(u->>'name')||' ('||(u->>'active_courses')||' active courses)')) from jsonb_array_elements(unis) u),'[]'),
 'universities',unis,'recent',coalesce((select jsonb_agg(x order by x.created_at desc) from
 (select cohort_id,scope,size,reason,request_key,created_at from pipeline.intake_ui_requests where requested_by=auth.uid() order by created_at desc limit security.pipeline_num_v1('run_now.history_rows',20)::int) x),'[]'),
 'diagnostic',jsonb_build_object('approved',false));
 elsif p_view='preview' then return security.intake_ui_preview_v1(p_args->>'scope',(p_args->>'size')::integer);
 elsif p_view='verify' then
 c:=(p_args->>'cohort_id')::uuid;
 select * into req from pipeline.intake_ui_requests where cohort_id=c and requested_by=auth.uid();
 if not found then raise exception 'cohort is unavailable to this operator' using errcode='42501'; end if;
 r:=security.run_now_cohort_verify_v1(c);
 -- Decorate read-back; do not alter either frozen consumer response shape or their functions.
 r:=r||jsonb_build_object('courses',coalesce((select jsonb_agg(x||jsonb_build_object(
 'course_title',(select coalesce(display_title,canonical_title) from catalogue.courses where id=(x->>'course_id')::uuid),
 'provider_name',(select coalesce(display_name,canonical_name) from catalogue.providers where id=(x->>'provider_id')::uuid),
 'publication',jsonb_build_object(
 'catalogue',case when jsonb_array_length(x->'added')>0 and not exists(select 1 from jsonb_array_elements(x->'added') a where
 not coalesce(security.intake_ui_values_match_v1(a->'after',x->'now'),false)) then 'verified' else 'unverified' end,
 'website',case when jsonb_array_length(x->'added')>0 and not exists(select 1 from jsonb_array_elements(x->'added') a where
 not coalesce(security.intake_ui_values_match_v1(a->'after',x->'website_intakes'),false)) then 'verified' else 'unverified' end,
 'zoho',case when jsonb_typeof(x->'zoho_intakes') is distinct from 'array' then 'unsupported'
 when jsonb_array_length(x->'added')>0 and not exists(select 1 from jsonb_array_elements(x->'added') a where
 not coalesce(security.intake_ui_values_match_v1(a->'after',x->'zoho_intakes'),false)) then 'verified' else 'unverified' end)) order by (x->>'pick')::int)
 from jsonb_array_elements(r->'courses') x),'[]'));
 return r||jsonb_build_object('as_at',clock_timestamp(),'saved_request',to_jsonb(req)-'preview_token'-'requested_by',
 'runs',coalesce((select jsonb_agg(jsonb_build_object('run_id',j.id,'state',j.state,'outcome',j.outcome,'reason',j.reason,'started_at',j.started_at,'finished_at',j.finished_at,'error',j.error)||coalesce(j.result,'{}') order by j.created_at)
 from pipeline.admin_jobs j where j.kind='job_run_now' and j.args->>'cohort_id'=c::text),'[]'),
 'next_action','Compare catalogue and consumer read-backs against the fixed source evidence. Missing/unsupported consumer data is unverified, never a pass.');
 else raise exception 'unknown intake read view'; end if;
end $function$
