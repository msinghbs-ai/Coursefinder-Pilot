CREATE OR REPLACE FUNCTION public.svc_provider_facts_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, r.search_domain
      from pipeline.provider_fact_search s join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
     where (s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < 3))
       and (s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))
     order by (s.kind <> 'fee_schedule'), s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$
