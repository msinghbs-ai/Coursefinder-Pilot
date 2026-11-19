CREATE OR REPLACE FUNCTION public.admin_intake_cohort_prepare_v1(p_scope text, p_size integer, p_reason text, p_preview_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tok jsonb; body jsonb; sig text; s jsonb; c uuid; existing pipeline.intake_ui_requests%rowtype;
begin
 if auth.uid() is null or security.current_role_rank()<greatest(coalesce((select control_rank from pipeline.automation_catalogue where jobname='intake-dates-apply'),6),3) then
 raise exception 'your role cannot prepare this job' using errcode='42501'; end if;
 if coalesce(btrim(p_reason),'')='' then raise exception 'an audited reason is required'; end if;
 tok:=p_preview_token::jsonb; body:=tok->'body';
 select encode(extensions.hmac(body::text,secret,'sha256'),'hex') into sig from pipeline.intake_ui_signing_key;
 if sig is null or tok->>'signature' is distinct from sig or body->>'requester' is distinct from auth.uid()::text or body->>'scope' is distinct from p_scope
 or (body->>'size')::integer is distinct from p_size then raise exception 'invalid or foreign preview'; end if;
 -- Serialise preparation of the same preview; this is not the intake job's lock.
 perform pg_advisory_xact_lock(hashtextextended(p_preview_token,0)); -- fixed: token-level duplicate preparation guard
 select * into existing from pipeline.intake_ui_requests where preview_token=p_preview_token;
 if found then
 if existing.reason<>btrim(p_reason) then raise exception 'fixed cohort reason cannot change'; end if;
 return jsonb_build_object('cohort_id',existing.cohort_id,'preview_token',p_preview_token,'request_key',existing.request_key,'reason',existing.reason); end if;
 if (body->>'expires_at')::timestamptz<clock_timestamp() then raise exception 'preview expired; preview again'; end if;
 s:=security.intake_ui_selection_v1(p_scope,p_size);
 if encode(extensions.digest(s::text,'sha256'),'hex') is distinct from body->>'fingerprint' then raise exception 'selection or evidence changed; preview again'; end if;
 if jsonb_array_length(s->'courses')=0 then raise exception 'no eligible courses: inspect missing evidence and current intake rules'; end if;
 insert into pipeline.run_now_cohorts(job,label,selection_rule,selection,requested_by,reason)
 values('intake-dates-apply','Operator intake cohort',s->>'rule',s-'courses',auth.uid(),btrim(p_reason)) returning id into c;
 insert into pipeline.run_now_cohort_members(cohort_id,course_id,provider_id,pick,pattern,fills,evidence)
 select c,(m->>'course_id')::uuid,(m->>'provider_id')::uuid,(m->>'pick')::integer,m->>'pattern',array(select jsonb_array_elements_text(m->'fills')),m->'at_selection'
 from jsonb_array_elements(s->'courses') m;
 insert into pipeline.intake_ui_requests(cohort_id,requested_by,preview_token,scope,size,reason)
 values(c,auth.uid(),p_preview_token,p_scope,p_size,btrim(p_reason)) returning * into existing;
 insert into pipeline.admin_control_events(area,action,target,detail,actor)
 values('run_now','cohort_prepared','intake-dates-apply',jsonb_build_object('cohort_id',c,'selection',s-'courses'),auth.uid());
 return jsonb_build_object('cohort_id',c,'preview_token',p_preview_token,'request_key',existing.request_key,'reason',existing.reason);
end $function$
