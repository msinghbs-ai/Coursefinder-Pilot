CREATE OR REPLACE FUNCTION security.course_entry_correction_v1(p_item uuid, p_actor uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o pipeline.layer4_review_items%rowtype; g record; v_chk jsonb; v_job uuid; v_enrich bigint; v_id uuid;
begin
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'give a reason (kept in the record)'; end if;
  select * into o from pipeline.layer4_review_items where id = p_item for update;
  if o.id is null then raise exception 'no such Layer 4 item'; end if;
  select pg.url, pg.evidence_id into g from pipeline.coverage_course_pages pg where pg.course_id = o.entity_id;
  v_chk := security.course_entry_correction_check_v1(p_item, o.entity_id, g.url);
  if not (v_chk->>'ok')::boolean then raise exception 'No corrected read (D-R2): %. Nothing was changed', v_chk->>'why' using errcode = '55000'; end if;
  if exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = p_item and s.state = 'requested') then
    raise exception 'No corrected read (D-R2): a corrected read of this item is already asked for. Nothing was changed' using errcode = '55000';
  end if;
  if exists (select 1 from pipeline.field_enrich_items f where f.course_id = o.entity_id and f.field = 'entry_requirements' and f.state in ('queued', 'waiting', 'ai', 'leased')) then
    raise exception 'No corrected read (D-R2): a read of this course is already in progress. Nothing was changed' using errcode = '55000';
  end if;
  v_job := security.course_entry_read_enqueue_v1(o.entity_id, p_actor, 'Corrected read (D-R2) of Layer 4 item ' || p_item || ': ' || btrim(p_reason));
  select f.id into v_enrich from pipeline.field_enrich_items f where f.job_id = v_job and f.course_id = o.entity_id and f.field = 'entry_requirements';
  insert into pipeline.aer_read_supersessions(old_item_id, course_id, source_url, old_evidence_id, enrich_item_id, job_id, requested_by, reason)
  values (p_item, o.entity_id, g.url, o.evidence_id, v_enrich, v_job, p_actor, btrim(p_reason)) returning id into v_id;
  return jsonb_build_object('request_id', v_id, 'job_id', v_job, 'enrich_item_id', v_enrich, 'review_item_id', p_item);
end $function$
