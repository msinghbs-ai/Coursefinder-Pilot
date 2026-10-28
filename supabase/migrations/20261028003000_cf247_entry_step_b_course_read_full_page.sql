-- CF-247 Track C Step B, B1 follow-up (28 Oct 2026; decision record admin docs/platform/ENTRY-REQUIREMENTS-STEP-B-DECISION-2026-10-28.md).
-- The decided slice read of RMIT BH126 ran at 21:39 (item 227056, US$0.0024) and returned "the page does not state it": the worker gave the
-- model only the page's <main> element, and RMIT prints its entry requirements outside it (the stored copy holds them: the adapter read
-- "You must have successfully completed the Victorian Certificate of Education (VCE) ... Prerequisites ..."). Worker v0.49.1 reads the
-- whole page text (navigation, header and footer left out).
-- 1. security.course_entry_read_enqueue_v1: a person's or a decided read releases the course's earlier "no value" hold on this field first
--    (as Read with AI does), so the item is not refused by the item gate.
-- 2. The slice read once more follows in its own migration (20261028004000), merged only after worker v0.49.1 is verified live, so the
--    read cannot be taken by the v0.49.0 worker.
-- Replaces: security.course_entry_read_enqueue_v1 (same name, flag release added)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched. No new job.

do $$ begin
  if md5(pg_get_functiondef('security.course_entry_read_enqueue_v1(uuid,uuid,text)'::regprocedure)) <> '77053f34121c28c633f10d2318cc9f4b' then
    raise exception 'live security.course_entry_read_enqueue_v1 differs from the definition this change replaces';
  end if;
end $$;

create or replace function security.course_entry_read_enqueue_v1(p_course uuid, p_by uuid, p_reason text) returns uuid
language plpgsql security definer set search_path to '' as $$
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
end $$;
revoke all on function security.course_entry_read_enqueue_v1(uuid, uuid, text) from public, anon, authenticated;
comment on function security.course_entry_read_enqueue_v1(uuid, uuid, text) is 'CF-247 Track C Step B (B1): one Enrich fields task with one entry_requirements item for one course (stored page only); releases the field''s earlier no-value hold first.';
