-- CF-CHG-20260823-029
create or replace function public.svc_layer2_trial_provider_id(p_provider_key text)
returns uuid language plpgsql stable security definer set search_path=pg_catalog,public,pipeline,auth as $$
declare v_id uuid; begin if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if; select id into v_id from pipeline.layer2_acquisition_providers where provider_key=p_provider_key; if v_id is null then raise exception 'provider not found' using errcode='P0002'; end if; return v_id; end $$;
create or replace function public.svc_layer2_trial_course_update(p_trial_course_id uuid,p_status text,p_post_factual jsonb default '{}'::jsonb,p_post_context jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=pg_catalog,public,pipeline,auth as $$ begin if auth.role()<>'service_role' then raise exception 'service role required' using errcode='42501'; end if; update pipeline.layer2_completeness_trial_courses set status=p_status,post_factual=coalesce(p_post_factual,'{}'::jsonb),post_context=coalesce(p_post_context,'{}'::jsonb) where id=p_trial_course_id; if not found then raise exception 'trial course not found' using errcode='P0002'; end if; end $$;
revoke all on function public.svc_layer2_trial_provider_id(text) from public,anon,authenticated;
revoke all on function public.svc_layer2_trial_course_update(uuid,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.svc_layer2_trial_provider_id(text) to service_role;
grant execute on function public.svc_layer2_trial_course_update(uuid,text,jsonb,jsonb) to service_role;
