-- CF-CHG-20260823-029
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
  v_summary := pipeline.layer2_provider_trial_summary(p_trial_id);
  return jsonb_build_object('ok',true,'trial',v_trial,'courses',v_courses,'provider_summary',coalesce(v_summary,'[]'::jsonb));
end $$;
revoke all on function public.svc_layer2_trial_detail(uuid) from public, anon, authenticated;
grant execute on function public.svc_layer2_trial_detail(uuid) to service_role;
