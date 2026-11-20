CREATE OR REPLACE FUNCTION public.admin_course_description_queue(p_action text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb := coalesce(p_args, '{}'::jsonb);
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 4 then raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;
  if p_action is null or p_action not in ('summary', 'items', 'held_reasons', 'claim_words', 'sample', 'capacity', 'pack') then raise exception 'unknown action %', p_action using errcode = '22023'; end if;
  return case p_action
    when 'summary' then security.course_description_summary_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'recheck')::boolean, false))
    when 'items' then security.course_description_items_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0), coalesce((a->>'sample')::boolean, false))
    when 'held_reasons' then security.course_description_held_reasons_v1()
    when 'claim_words' then security.course_description_claim_eval_v1(case when jsonb_typeof(a->'words') = 'array' then a->'words' end)
    when 'capacity' then security.course_description_capacity_v1()
    when 'pack' then security.course_description_pack_v1(nullif(a->>'provider_id', '')::uuid, coalesce((a->>'offset')::int, 0))
    else security.course_description_sample_report_v1() end;
end $function$
