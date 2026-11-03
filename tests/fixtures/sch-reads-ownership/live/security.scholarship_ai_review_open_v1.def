CREATE OR REPLACE FUNCTION security.scholarship_ai_review_open_v1(p_extraction bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e pipeline.scholarship_ai_extractions%rowtype; v_root bigint; v_ids bigint[]; v_prev pipeline.scholarship_ai_reviews%rowtype; v_new bigint;
begin
  select * into e from pipeline.scholarship_ai_extractions where id = p_extraction;
  if e.id is null then return null; end if;
  select coalesce(q.root_id, q.id) into v_root from pipeline.scholarship_ai_queue q where q.id = e.queue_id;
  v_ids := array(select x.id from pipeline.scholarship_ai_extractions x join pipeline.scholarship_ai_queue q on q.id = x.queue_id where coalesce(q.root_id, q.id) = v_root order by x.id);
  select * into v_prev from pipeline.scholarship_ai_reviews r
   where r.status in ('admitted', 'refused') and r.url = e.url and coalesce(r.storage_path, '') = coalesce(e.storage_path, '') order by r.decided_at desc limit 1;
  if v_prev.id is not null then
    insert into pipeline.scholarship_ai_reviews(candidate_id, scholarship_id, provider_id, url, storage_path, extraction_ids, reason, status, decided_at, note, decision)
    values (e.candidate_id, e.scholarship_id, e.provider_id, e.url, e.storage_path, v_ids, p_reason, 'pending', null, null, null) returning id into v_new;
    return security.scholarship_ai_review_apply_v1(v_new, case v_prev.status when 'admitted' then 'admit' else 'refuse' end, null,
             'Same page copy as review ' || v_prev.id || ' (decided ' || to_char(v_prev.decided_at at time zone 'Australia/Melbourne', 'DD Mon YYYY') || '): ' || coalesce(v_prev.note, ''), v_prev.decided_by)
           || jsonb_build_object('exception_from', v_prev.id);
  end if;
  update pipeline.scholarship_ai_reviews set extraction_ids = v_ids, reason = p_reason, storage_path = e.storage_path
   where status = 'pending' and ((e.candidate_id is not null and candidate_id = e.candidate_id) or (e.scholarship_id is not null and scholarship_id = e.scholarship_id))
  returning id into v_new;
  if v_new is null then
    insert into pipeline.scholarship_ai_reviews(candidate_id, scholarship_id, provider_id, url, storage_path, extraction_ids, reason)
    values (e.candidate_id, e.scholarship_id, e.provider_id, e.url, e.storage_path, v_ids, p_reason) returning id into v_new;
  end if;
  return jsonb_build_object('review', v_new, 'reason', p_reason);
end $function$
