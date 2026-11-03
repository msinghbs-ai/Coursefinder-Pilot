CREATE OR REPLACE FUNCTION security.course_entry_read_enqueue_v1(p_course uuid, p_by uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job uuid; c record;
begin
  select x.id, x.provider_id, x.canonical_title into c from catalogue.courses x where x.id = p_course;
  -- a person (or the decided slice) asked, with a reason: an earlier "no value" hold on this field is released so the read is not refused
  update pipeline.enrichment_flags f set state = 'released', released_at = now(), released_by = p_by, release_kind = 'person',
         release_reason = 'Entry requirements read: ' || p_reason, updated_at = now()
   where f.entity = 'course' and f.entity_key = p_course::text and f.reason_code = 'enrich_no_value' and f.state in ('raised', 'counting') and f.field = 'entry_requirements';
  insert into pipeline.admin_jobs(kind, lane, state, title, args, progress, requested_by, reason, scope)
  values ('enrich_fields', 'enrich', 'queued', left('Entry requirements · ' || c.canonical_title, 200),
          jsonb_build_object('read_now', true, 'entry_read', true, 'countries', '[]'::jsonb, 'provider_ids', jsonb_build_array(c.provider_id), 'course_ids', jsonb_build_array(c.id),
                             'fields', jsonb_build_array('entry_requirements'), 'ai', true, 'scraper', false),
          jsonb_build_object('done', 0, 'total', 1), p_by, p_reason, '1 course')
  returning id into v_job;
  insert into pipeline.field_enrich_items(job_id, provider_id, course_id, field, state) values (v_job, c.provider_id, c.id, 'entry_requirements', 'queued') on conflict do nothing;
  if not exists (select 1 from pipeline.field_enrich_items f where f.job_id = v_job) then raise exception 'the entry requirements item was refused by the item gate'; end if;
  return v_job;
end $function$
