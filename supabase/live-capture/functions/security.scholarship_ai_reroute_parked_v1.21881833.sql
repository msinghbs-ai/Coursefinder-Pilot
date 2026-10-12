CREATE OR REPLACE FUNCTION security.scholarship_ai_reroute_parked_v1(p_job uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a record; v_n int; v_s int;
begin
  select * into a from security.scholarship_ai_active_v1();
  if a.model_code is null then raise exception 'set the model chain first'; end if;
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, job_id, scholarship_id, provider_id, url)
  select a.model_code, a.prompt_version, 'reread', p_job, s.id, s.provider_id, coalesce(sp.final_url, sp.url)
    from scholarship.scholarships s join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
   where s.lifecycle_status = 'active'
     and (s.publication_status is distinct from 'published' or exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null))
     and not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = s.id and q.state in ('queued', 'leased'));
  get diagnostics v_n = row_count;
  with x as (
    update pipeline.layer4_review_items r set status = 'superseded', decided_at = now(),
           change_control_ref = coalesce(r.change_control_ref || '; ', '') || 'CF-247 v2.15.250: rerouted to the scholarship AI reader'
     where r.status = 'pending' and r.entity_type = 'scholarship' returning r.id, r.entity_id, r.field_code)
  insert into pipeline.layer4_reroutes(item_id, entity_type, entity_id, field_code, route, note) select x.id, 'scholarship', x.entity_id, x.field_code, 'scholarship_ai', 'parked item' from x;
  get diagnostics v_s = row_count;
  perform security.scholarship_ai_fire_v1();
  return jsonb_build_object('queued', v_n, 'layer4_items', v_s);
end $function$
