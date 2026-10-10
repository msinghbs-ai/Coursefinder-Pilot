-- CF-CHG-20260823-029
-- Keep private pipeline/catalogue tables out of browser/Edge PostgREST schema exposure.
create or replace function public.svc_layer2_trial_list()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pipeline, catalogue, auth
as $$
declare v_result jsonb;
begin
  if auth.role() <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  select jsonb_build_object('ok',true,'trials',coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'country_id',t.country_id,'provider_id',t.provider_id,'trial_mode',t.trial_mode,
    'requested_batch_size',t.requested_batch_size,'status',t.status,'baseline_summary',t.baseline_summary,
    'result_summary',t.result_summary,'recommendation',t.recommendation,'change_control_ref',t.change_control_ref,
    'uat_ref',t.uat_ref,'started_at',t.started_at,'completed_at',t.completed_at,'created_at',t.created_at,
    'provider',case when p.id is null then null else jsonb_build_object('id',p.id,'canonical_name',p.canonical_name,'display_name',p.display_name) end
  ) order by t.created_at desc),'[]'::jsonb)) into v_result
  from (select * from pipeline.layer2_completeness_trials order by created_at desc limit 50) t
  left join catalogue.providers p on p.id=t.provider_id;
  return v_result;
end $$;

create or replace function public.svc_layer2_trial_detail(p_trial_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pipeline, catalogue, auth
as $$
declare v_trial jsonb; v_courses jsonb; v_summary jsonb;
begin
  if auth.role() <> 'service_role' then raise exception 'service role required' using errcode='42501'; end if;
  select to_jsonb(t) into v_trial from pipeline.layer2_completeness_trials t where t.id=p_trial_id;
  if v_trial is null then raise exception 'trial not found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(to_jsonb(r) || jsonb_build_object(
    'course',jsonb_build_object('id',c.id,'provider_id',c.provider_id,'canonical_title',c.canonical_title,'display_title',c.display_title,'course_code',c.course_code,'stable_key',c.stable_key,'course_url',c.course_url),
    'official_url',coalesce(c.course_url,(select l.url from catalogue.course_links l where l.course_id=r.course_id order by (l.link_type='official_course') desc,l.is_primary desc,l.last_verified_at desc nulls last,l.created_at desc limit 1)),
    'links',coalesce((select jsonb_agg(jsonb_build_object('course_id',l.course_id,'url',l.url,'link_type',l.link_type,'is_primary',l.is_primary,'status',l.status,'last_verified_at',l.last_verified_at,'created_at',l.created_at) order by l.is_primary desc,l.last_verified_at desc nulls last,l.created_at desc) from catalogue.course_links l where l.course_id=r.course_id),'[]'::jsonb)
  ) order by r.sample_rank),'[]'::jsonb) into v_courses
  from pipeline.layer2_completeness_trial_courses r left join catalogue.courses c on c.id=r.course_id where r.trial_id=p_trial_id;
  select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into v_summary from pipeline.layer2_provider_trial_summary(p_trial_id) s;
  return jsonb_build_object('ok',true,'trial',v_trial,'courses',v_courses,'provider_summary',v_summary);
end $$;

revoke all on function public.svc_layer2_trial_list() from public, anon, authenticated;
revoke all on function public.svc_layer2_trial_detail(uuid) from public, anon, authenticated;
grant execute on function public.svc_layer2_trial_list() to service_role;
grant execute on function public.svc_layer2_trial_detail(uuid) to service_role;
comment on function public.svc_layer2_trial_list() is 'CF-CHG-20260823-029: service-only M2.1 trial read boundary for JWT Edge orchestration; avoids exposing private pipeline schema through PostgREST.';
comment on function public.svc_layer2_trial_detail(uuid) is 'CF-CHG-20260823-029: service-only M2.1 trial detail boundary for JWT Edge orchestration; preserves private pipeline schema.';
