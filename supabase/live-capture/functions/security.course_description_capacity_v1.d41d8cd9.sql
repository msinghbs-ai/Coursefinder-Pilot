CREATE OR REPLACE FUNCTION security.course_description_capacity_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (
    select security.pipeline_num_v1('layer4.lifecycle_report_days', 7) days, security.pipeline_num_v1('layer4.target_days', 7) target,
           security.layer4_pace_v1() -> 'course_description_first_read' pace, security.pipeline_num_v1('layer4.pace_default_minutes', 3) dflt,
           security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) gmax),
  c as (select class, count(*) n from security.course_description_reconcile_v1(null, false, 0) group by class),
  held as (select count(*) n from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'),
  q as (
    select count(*) filter (where i.status = 'pending') pending,
           count(*) filter (where i.created_at > now() - make_interval(days => s.days::int)) arrived,
           count(*) filter (where i.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3') and i.decided_at > now() - make_interval(days => s.days::int) and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = i.id and md.layer2_state->>'actor_kind' = 'machine')) decided,
           count(*) filter (where i.status in ('approved', 'edited_approved') and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = i.id and md.layer2_state->>'actor_kind' = 'machine')) approved_ever,
           count(*) filter (where i.status in ('approved', 'edited_approved') and exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = i.id and md.layer2_state->>'actor_kind' = 'machine')) approved_by_machine,
           min(i.created_at) filter (where i.status = 'pending') oldest
      from pipeline.layer4_review_items i cross join s where i.entity_type = 'course' and i.field_code = 'course_description_first_read'),
  m as (select s.*, coalesce((s.pace ->> 'minutes')::numeric, s.dflt) mins, case when s.pace is null then 'default' else coalesce(s.pace ->> 'basis', 'default') end basis,
               q.pending, q.arrived, q.decided, q.approved_ever, q.approved_by_machine, q.oldest, h.n held_first, coalesce((select n from c where class = 'ready'), 0) ready
          from s cross join q cross join held h)
  select jsonb_build_object(
    'note', 'Measurement only. A person decides every description; this plans the reviewer time and decides nothing.',
    'pending', m.pending, 'ready', m.ready, 'not_ready', m.pending - m.ready, 'held_first_readings_behind_the_provider_cap', m.held_first,
    'would_wait_for_a_person_after_the_cap_frees', m.pending + m.held_first, 'oldest_waiting', m.oldest,
    'window_days', m.days, 'arrived_in_window', m.arrived, 'arriving_a_day', round(m.arrived / nullif(m.days, 0), 1),
    'decided_in_window', m.decided, 'decided_a_day', round(m.decided / nullif(m.days, 0), 1), 'approved_ever', m.approved_ever, 'approved_by_machine', m.approved_by_machine,
    'minutes_an_item', m.mins, 'pace_basis', m.basis,
    'hours_to_clear_waiting', round(m.pending * m.mins / 60.0, 1),
    'hours_to_clear_waiting_and_held', round((m.pending + m.held_first) * m.mins / 60.0, 1),
    'target_days', m.target,
    'items_a_day_to_clear_waiting_in_target', ceil(m.pending / nullif(m.target, 0)),
    'items_a_day_needed_incl_arrivals', ceil(m.pending / nullif(m.target, 0) + m.arrived / nullif(m.days, 0)),
    'reviewer_hours_a_day_needed', round((m.pending / nullif(m.target, 0) + m.arrived / nullif(m.days, 0)) * m.mins / 60.0, 1),
    'days_to_clear_at_current_decisions', case when m.decided > 0 then round(m.pending / (m.decided / nullif(m.days, 0)), 1) end,
    'back_pressure', jsonb_build_object('global_max', m.gmax, 'on', m.gmax > 0, 'waiting_now', m.pending, 'new_readings_paused', m.gmax > 0 and m.pending >= m.gmax))
  from m
$function$
