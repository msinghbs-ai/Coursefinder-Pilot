CREATE OR REPLACE FUNCTION security.boost_study_load_review_feed_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cap int := security.pipeline_num_v1('boost.layer4_open_max', 400)::int;
  v_prompt text := (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' order by q.prompt_version desc limit 1);
  v_closed int := 0; v_opened int := 0; v_room int;
begin
  perform pg_advisory_xact_lock(hashtext('cf247:boost_study_load_review_feed'));  -- fixed: one writer
  update pipeline.boost_study_load_reviews r set status = 'superseded', decided_at = now(), reason = 'the course gained a study load or a manual lock elsewhere'
   where r.status = 'open'
     and (exists (select 1 from catalogue.courses c where c.id = r.course_id and c.study_load is not null)
          or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id')));
  get diagnostics v_closed = row_count;
  v_room := v_cap - (select count(*) from pipeline.boost_study_load_reviews where status = 'open');
  if v_room > 0 and v_prompt is not null then
    insert into pipeline.boost_study_load_reviews (staging_id, course_id, provider_id, evidence_id, source_url, prompt_version, answer, problems)
    select d.id, d.entity_id, c.provider_id, d.evidence_id, d.source_url, d.prompt_version, d.answer, coalesce(d.verdict->'problems', '[]'::jsonb)
      from (select distinct on (s.entity_id) s.* from pipeline.boost_inbound_staging s
             where s.lane = 'study_load' and s.worker_status = 'rejected' and s.prompt_version = v_prompt
             order by s.entity_id, s.id desc) d
      join catalogue.courses c on c.id = d.entity_id
     where c.study_load is null
       and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = d.entity_id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))
       -- a course already reviewed for this page (any status) is not sent again; a course with an open review waits for it
       and not exists (select 1 from pipeline.boost_study_load_reviews r where r.course_id = d.entity_id and (r.status = 'open' or r.evidence_id is not distinct from d.evidence_id))
     order by d.id
     limit v_room;
    get diagnostics v_opened = row_count;
  end if;
  return jsonb_build_object('opened', v_opened, 'superseded', v_closed, 'open', (select count(*) from pipeline.boost_study_load_reviews where status = 'open'), 'cap', v_cap, 'prompt_version', v_prompt);
end $function$
