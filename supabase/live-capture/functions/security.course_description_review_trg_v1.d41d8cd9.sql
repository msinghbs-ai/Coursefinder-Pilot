CREATE OR REPLACE FUNCTION security.course_description_review_trg_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item bigint := case when coalesce(new.proposed_value->>'item_id', '') ~ '^\d+$' then (new.proposed_value->>'item_id')::bigint end; v_pid uuid;
begin
  if v_item is not null then
    update pipeline.field_enrich_items set state = case when new.status in ('approved', 'edited_approved') then 'filled' else 'skipped' end,
           reason = case when new.status in ('approved', 'edited_approved') then null else 'not admitted in Layer 4 (' || new.status || ')' end, updated_at = now()
     where id = v_item and state = 'review';
  end if;
  select c.provider_id into v_pid from catalogue.courses c where c.id = new.entity_id;
  if new.status in ('approved', 'edited_approved') then
    perform security.course_description_release_held_v1(v_pid);
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  perform security.course_description_promote_held_v1(v_pid);
  return null;
end $function$
