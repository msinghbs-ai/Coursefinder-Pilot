create or replace function security.enrich_item_in_flight_v1(p_provider uuid, p_course uuid, p_field text) returns boolean
language sql stable security definer set search_path = '' as $$
  -- the standing gap queue's rule (security.field_gap_queue_tick_v1): the latest item of this course (or university) and field is being
  -- worked on, or waits for a person
  select coalesce(case when p_course is not null
    then (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id = p_course and e.field = p_field and e.provider_id = p_provider order by e.id desc limit 1)
    else (select e.state in ('queued', 'waiting', 'ai', 'leased', 'review') from pipeline.field_enrich_items e
           where e.course_id is null and e.provider_id = p_provider and e.field = p_field order by e.id desc limit 1) end, false)
$$;
