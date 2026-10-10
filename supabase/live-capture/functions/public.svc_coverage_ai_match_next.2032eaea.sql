CREATE OR REPLACE FUNCTION public.svc_coverage_ai_match_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security'
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select q.id from pipeline.coverage_ai_match q
      left join pipeline.course_priority cp on cp.course_id = q.course_id
      left join pipeline.provider_priority pp on pp.provider_id = q.provider_id
     where q.state = 'ready' or (q.state = 'leased' and q.leased_until < now())
     order by (q.state = 'leased'), coalesce(cp.sort, 1000000), coalesce(pp.rank, 100000), q.id
     limit greatest(1, least(coalesce(p_limit, 20), 80)) for update of q skip locked),
  upd as (update pipeline.coverage_ai_match q set state = 'leased', leased_until = now() + interval '10 minutes' from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'course_id', u.course_id, 'provider_id', u.provider_id, 'title', co.canonical_title,
           'code', case when co.course_code ~ '^[0-9a-f]{8}-' then null else co.course_code end,
           'level', (select sl.name from ref.study_levels sl where sl.id = co.study_level_id),
           'provider', coalesce(pr.display_name, pr.canonical_name), 'country', security.coverage_country(u.provider_id),
           'candidates', u.candidates)), '[]'::jsonb)
    into v from upd u join catalogue.courses co on co.id = u.course_id join catalogue.providers pr on pr.id = u.provider_id;
  return v;
end $function$
