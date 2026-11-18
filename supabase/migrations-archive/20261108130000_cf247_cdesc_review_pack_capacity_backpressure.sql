-- CF-247 C-DESC (course descriptions), 8 Nov 2026: a review pack and the review capacity for the course descriptions waiting in Layer 4, a global back-pressure
-- switch for the standing description queue, and a governed way to retire proposals that can no longer be approved.
-- Platform Admin directive 8 Nov 2026 14:06 (Melbourne): reconcile the 163 live descriptions and the outstanding Layer 4 queue; fix the producer-to-review handoffs;
-- human-approved items must progress; NO auto-approval; claim and evidence guards unchanged; present review packets and capacity numbers.
-- Mandate 8 Nov 2026 (docs/platform/nz-enrichment-brief/2026-11-08-cross-domain-autonomous-delivery-closure.md, lane C-DESC): "Design a review-capacity plan; do not create
-- endless new proposals when no reviewer can decide."
--
-- What this adds (read-only unless stated; nothing here approves, rejects, edits or admits a description, and no check is weakened):
--   1. security.course_description_capacity_v1(): pending, ready, held first readings, inflow and decisions a day, minutes an item (the measured Layer 4 pace, else the
--      Layer 4 default), hours to clear, items a day needed to clear within the Layer 4 target, and the back-pressure state. Read only.
--   2. security.course_description_pack_v1(provider, offset): the same waiting items as the Inbox list, ordered for a reviewer: universities whose decision frees the most
--      held readings first (a decision lets the provider's held readings take the freed places: migration 20261107120000), within a university the items with no flag first.
--      Flags are objective and never decide anything: same_words_elsewhere, claim_word, marketing_word, money_or_year.
--   3. public.admin_course_description_queue gains the actions 'capacity' and 'pack' (same rank gate: Pipeline Operator or above).
--   4. enrich.course_description_pending_global_max (ships 0 = off): when set, the standing gap queue stops queueing new description readings while this many descriptions
--      already wait for a person. security.enrich_course_text_gaps_v1 is replaced under its live md5 guard.
--   5. security.course_description_retire_stale_v1() + job course-description-stale-retire (hourly): a waiting proposal whose course is no longer active, or already has a
--      description another way, is superseded (the existing pipeline.layer4_supersessions record, reason entity_retired / covered_by_active). Ships OFF behind
--      enrich.course_description_stale_supersede_on. It never approves or rejects; a proposal whose page changed, or whose course is locked, stays with a person.
--
-- Replaces: security.enrich_course_text_gaps_v1 (md5-guarded; the same selection, plus the global back-pressure line); public.admin_course_description_queue (md5-guarded; two actions added)
-- Retires: nothing
-- Consumer API: untouched (G3). catalogue.courses.description is not written here; no website_v2_*, website_edge_*, zoho_edge_*, api.* or edge function is read or changed.
-- Guards: live md5s read from production 8 Nov 2026 ~03:40 UTC: security.enrich_course_text_gaps_v1(text[]) a6d0da8f6d6fd7d31c6c39c707e2d824;
--   public.admin_course_description_queue(text,jsonb) a7bb9ff0f964c6caaf2537e5ae36c084.

do $guard$
declare v_g text := pg_get_functiondef('security.enrich_course_text_gaps_v1(text[])'::regprocedure);
        v_q text := pg_get_functiondef('public.admin_course_description_queue(text,jsonb)'::regprocedure);
begin
  if md5(v_g) <> 'a6d0da8f6d6fd7d31c6c39c707e2d824' and v_g not like '%course_description_pending_global_max%' then
    raise exception 'security.enrich_course_text_gaps_v1 is % and not the guarded definition a6d0da8f6d6fd7d31c6c39c707e2d824 (nor already replaced); re-read it and re-plan', md5(v_g);
  end if;
  if md5(v_q) <> 'a7bb9ff0f964c6caaf2537e5ae36c084' and v_q not like '%course_description_pack_v1%' then
    raise exception 'public.admin_course_description_queue is % and not the guarded definition a7bb9ff0f964c6caaf2537e5ae36c084 (nor already replaced); re-read it and re-plan', md5(v_q);
  end if;
end $guard$;

-- 1. settings (G2): label, range, unit, used_by ------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
('pipeline', 'enrich.course_description_pending_global_max', 'Course description: most waiting for a person before new readings pause',
 'When this many course descriptions already wait in Layer 4 for a person, the standing gap queue stops queueing new description readings until the number falls below it (readings already queued finish). It protects reviewers from an unbounded queue and the AI from reading pages that go stale before anyone decides. 0 = off (no global limit; the per-university limit enrich.course_description_pending_max still applies).',
 'number', '0'::jsonb, 0, 20000, 'descriptions', 1120, 'Course description and deadline', 'security.enrich_course_text_gaps_v1 (job field-gap-queue)',
 'CF-247 C-DESC 8 Nov 2026: review-capacity back-pressure, shipped off; the Platform Admin or Controller sets it from the capacity numbers'),
('pipeline', 'enrich.course_description_stale_supersede_on', 'Course description: retire proposals that can no longer be approved',
 'On (1): a waiting course description whose course is no longer active, or already has a description another way, is superseded by job course-description-stale-retire (recorded in pipeline.layer4_supersessions with the reason; never an approval or a rejection). Off (0): the job only counts them. A proposal whose page changed, or whose description is locked by hand, always stays with a person.',
 'number', '0'::jsonb, 0, 1, 'on/off', 1121, 'Course description and deadline', 'security.course_description_retire_stale_v1 (job course-description-stale-retire)',
 'CF-247 C-DESC 8 Nov 2026: orphan proposals (the course was archived or described another way while the proposal waited); ships off')
on conflict (toolset_key, key) do nothing;

-- 2. capacity (read only) ----------------------------------------------------------------------------------------------------------------------
create or replace function security.course_description_capacity_v1() returns jsonb language sql stable security definer set search_path = '' as $function$
  with s as (
    select security.pipeline_num_v1('layer4.lifecycle_report_days', 7) days, security.pipeline_num_v1('layer4.target_days', 7) target,
           security.layer4_pace_v1() -> 'course_description_first_read' pace, security.pipeline_num_v1('layer4.pace_default_minutes', 3) dflt,
           security.pipeline_num_v1('enrich.course_description_pending_global_max', 0) gmax),
  c as (select class, count(*) n from security.course_description_reconcile_v1(null, false, 0) group by class),
  held as (select count(*) n from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'),
  q as (
    select count(*) filter (where i.status = 'pending') pending,
           count(*) filter (where i.created_at > now() - make_interval(days => s.days::int)) arrived,
           count(*) filter (where i.status in ('approved', 'edited_approved', 'rejected', 'more_evidence', 'returned_layer2', 'returned_layer3') and i.decided_at > now() - make_interval(days => s.days::int)) decided,
           count(*) filter (where i.status in ('approved', 'edited_approved')) approved_ever,
           min(i.created_at) filter (where i.status = 'pending') oldest
      from pipeline.layer4_review_items i cross join s where i.entity_type = 'course' and i.field_code = 'course_description_first_read'),
  m as (select s.*, coalesce((s.pace ->> 'minutes')::numeric, s.dflt) mins, case when s.pace is null then 'default' else coalesce(s.pace ->> 'basis', 'default') end basis,
               q.pending, q.arrived, q.decided, q.approved_ever, q.oldest, h.n held_first, coalesce((select n from c where class = 'ready'), 0) ready
          from s cross join q cross join held h)
  select jsonb_build_object(
    'note', 'Measurement only. A person decides every description; this plans the reviewer time and decides nothing.',
    'pending', m.pending, 'ready', m.ready, 'not_ready', m.pending - m.ready, 'held_first_readings_behind_the_provider_cap', m.held_first,
    'would_wait_for_a_person_after_the_cap_frees', m.pending + m.held_first, 'oldest_waiting', m.oldest,
    'window_days', m.days, 'arrived_in_window', m.arrived, 'arriving_a_day', round(m.arrived / nullif(m.days, 0), 1),
    'decided_in_window', m.decided, 'decided_a_day', round(m.decided / nullif(m.days, 0), 1), 'approved_ever', m.approved_ever,
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
$function$;
comment on function security.course_description_capacity_v1() is 'CF-247 C-DESC (8 Nov 2026): review capacity for the course descriptions waiting in Layer 4 (pending, ready, held first readings, arrivals and decisions a day, minutes an item from the Layer 4 pace, hours and items a day to clear within the Layer 4 target, back-pressure state). Read only: decides nothing.';
revoke all on function security.course_description_capacity_v1() from public, anon, authenticated;

-- 3. the review pack (read only) -------------------------------------------------------------------------------------------------------------------
create or replace function security.course_description_pack_v1(p_provider uuid default null, p_offset integer default 0) returns jsonb language sql stable security definer set search_path = '' as $function$
  with cfg as (
    select coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb) claim,
           coalesce(security.toolset_setting('pipeline', 'enrich.course_description_marketing_words'), security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb) mkt),
  r as (select q.* from security.course_description_reconcile_v1(p_provider, false, 0) q where q.class = 'ready'),
  t as (
    select r.*, i.escalation_reason, i.before_value, i.proposed_value, i.evidence_id ev_id, c.course_code, pv.display_name pname, pv.canonical_name pcanon,
           btrim(i.proposed_value ->> 'description') d, md5(btrim(i.proposed_value ->> 'description')) h
      from r join pipeline.layer4_review_items i on i.id = r.item_id join catalogue.courses c on c.id = r.course_id left join catalogue.providers pv on pv.id = r.provider_id),
  same as (select h, count(*) n from t group by h),
  pub as (select md5(btrim(c.description)) h, count(*) n from catalogue.courses c where nullif(btrim(c.description), '') is not null group by 1),
  held as (select e.provider_id, count(*) n from pipeline.field_enrich_items e where e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%' group by 1),
  pc as (select provider_id, count(*) n from t group by 1),
  f as (
    select t.*, coalesce(hd.n, 0) unlock, pc.n in_university,
           (coalesce(same.n, 1) - 1) + coalesce(pub.n, 0) shared_n,
           exists (select 1 from jsonb_array_elements_text(cfg.claim) w where security.pdesc_has_term_v1(t.d, w)) has_claim,
           exists (select 1 from jsonb_array_elements_text(cfg.mkt) w where security.pdesc_has_term_v1(t.d, w)) has_mkt,
           t.d ~ '(\$|AUD|NZD|CAD)|\m(19|20)[0-9]{2}\M' has_fact
      from t cross join cfg left join same on same.h = t.h left join pub on pub.h = t.h left join held hd on hd.provider_id = t.provider_id left join pc on pc.provider_id = t.provider_id),
  g as (
    select f.*, array_remove(array[case when shared_n > 0 then 'same_words_elsewhere' end, case when has_claim then 'claim_word' end,
                                    case when has_mkt then 'marketing_word' end, case when has_fact then 'money_or_year' end], null) flags
      from f),
  o as (
    select g.*, dense_rank() over (order by g.unlock desc, g.in_university desc, coalesce(g.pname, g.pcanon), g.provider_id) prank,
           row_number() over (order by g.unlock desc, g.in_university desc, coalesce(g.pname, g.pcanon), g.provider_id, cardinality(g.flags), g.created_at, g.item_id) rn
      from g),
  pg as (select o.* from o where o.rn > greatest(coalesce(p_offset, 0), 0) and o.rn <= greatest(coalesce(p_offset, 0), 0) + security.pipeline_num_v1('layer4.inbox_page_size', 25)::int)
  select jsonb_build_object(
    'total', (select count(*) from o), 'offset', greatest(coalesce(p_offset, 0), 0), 'limit', security.pipeline_num_v1('layer4.inbox_page_size', 25)::int,
    'order', 'universities whose decision frees the most held readings first, then the larger queue; within a university the items with no flag first, then oldest',
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'provider_description', 'ref', pg.item_id::text, 'provider_id', pg.provider_id, 'provider', coalesce(pg.pname, pg.pcanon), 'subject', pg.course_title,
        'why', coalesce(nullif(pg.escalation_reason, ''), 'Needs a decision'), 'created_at', pg.created_at, 'ready', true,
        'detail', jsonb_strip_nulls(jsonb_build_object('field_code', 'course_description_first_read', 'course_id', pg.course_id, 'course_code', pg.course_code,
                    'code_label', case when pg.country = 'AU' then 'CRICOS' else 'Course code' end,
                    'before', pg.before_value, 'proposed', pg.proposed_value, 'evidence_id', pg.ev_id, 'captured_at', ev.captured_at, 'source_url', ev.source_url,
                    'reask', pg.reask,
                    'pack', jsonb_build_object('flags', to_jsonb(pg.flags), 'flag_count', cardinality(pg.flags), 'same_words_on_other_courses', pg.shared_n,
                                               'held_readings_this_decision_can_free', pg.unlock, 'waiting_in_university', pg.in_university, 'university_rank', pg.prank))))
        order by pg.rn)
      from pg left join pipeline.evidence_artifacts ev on ev.id = pg.ev_id), '[]'::jsonb))
$function$;
comment on function security.course_description_pack_v1(uuid, integer) is 'CF-247 C-DESC (8 Nov 2026): the course descriptions waiting for a person, ordered for review (universities whose decision frees the most held first readings first; within a university, items with no flag first) with objective flags (same words on other courses, claim word, marketing word, money or year). Read only: no flag decides, rejects or approves anything; every check of the admission path is unchanged.';
revoke all on function security.course_description_pack_v1(uuid, integer) from public, anon, authenticated;

-- 4. the Admin screen entry point: two actions added, same rank gate ----------------------------------------------------------------------------
create or replace function public.admin_course_description_queue(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $function$
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
end $function$;

-- 5. back-pressure in the standing gap queue: the live definition (md5 a6d0da8f...) plus one guard line for the description field ---------------------
create or replace function security.enrich_course_text_gaps_v1(p_fields text[])
 returns table(provider_id uuid, course_id uuid, field text, pri integer)
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int; v_gmax int := security.pipeline_num_v1('enrich.course_description_pending_global_max', 0)::int;
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    -- back-pressure (CF-247 C-DESC 8 Nov 2026): no new description readings while v_gmax descriptions already wait for a person (0 = off)
    continue when f = 'description' and v_gmax > 0
      and (select count(*) from pipeline.layer4_review_items q where q.entity_type = 'course' and q.field_code = 'course_description_first_read' and q.status = 'pending') >= v_gmax;
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc)
      select m.pid, m.cid, f, case when l.state is null then 1
                                    when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end
        from miss m left join last l on l.cid = m.cid
       where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => v_days)
              or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
         and not security.enrich_item_held_v1(m.cid, f)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
       order by 4, m.cid
       limit v_room;
  end loop;
end $function$;

-- 6. retire proposals that can no longer be approved (switch off by default) --------------------------------------------------------------------
create or replace function security.course_description_retire_stale_v1() returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_on boolean := security.pipeline_num_v1('enrich.course_description_stale_supersede_on', 0) >= 1; r record; v_n int := 0; v_ex int := 0; v_by jsonb := '{}'::jsonb; v_reason text;
        v_max int := security.pipeline_num_v1('layer4.reconcile_batch', 200)::int;
begin
  for r in select q.item_id, q.course_id, q.class, i.field_code, i.entity_type, i.entity_id, i.evidence_id
             from security.course_description_reconcile_v1(null, false, 0) q join pipeline.layer4_review_items i on i.id = q.item_id
            where q.class in ('course_inactive', 'already_filled') and i.status = 'pending'
            order by i.created_at limit v_max loop
    v_ex := v_ex + 1;
    v_reason := case r.class when 'course_inactive' then 'entity_retired' else 'covered_by_active' end;
    v_by := v_by || jsonb_build_object(v_reason, coalesce((v_by ->> v_reason)::int, 0) + 1);
    continue when not v_on;
    update pipeline.layer4_review_items set status = 'superseded', decided_at = now(),
           change_control_ref = left(coalesce(change_control_ref, '') || ' | superseded: ' || v_reason || ' (course description proposal can no longer be approved)', 400)
     where id = r.item_id and status = 'pending';
    continue when not found;
    insert into pipeline.layer4_supersessions(item_id, field_code, entity_type, entity_id, reason, covered_by_item, evidence, mode)
    values (r.item_id, r.field_code, r.entity_type, r.entity_id, v_reason, null,
            jsonb_build_object('class', r.class, 'evidence_id', r.evidence_id, 'by', 'course-description-stale-retire'), 'reconcile');
    if to_regclass('pipeline.layer4_item_readiness') is not null then
      execute 'update pipeline.layer4_item_readiness set item_status = ''superseded'', readiness = ''closed'', classified_at = now() where item_id = $1' using r.item_id;
    end if;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('on', v_on, 'examined', v_ex, 'superseded', v_n, 'by_reason', v_by);
end $function$;
comment on function security.course_description_retire_stale_v1() is 'CF-247 C-DESC (8 Nov 2026): while enrich.course_description_stale_supersede_on is 1, a waiting course description proposal whose course is no longer active (entity_retired) or already has a description (covered_by_active) is superseded and recorded in pipeline.layer4_supersessions. Never approves or rejects; page-changed and locked proposals stay with a person. Off: counts only.';
revoke all on function security.course_description_retire_stale_v1() from public, anon, authenticated;

-- 7. the job (G1: catalogued first; ships on, settles nothing while its switch is 0) -------------------------------------------------------------
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable, layer23_stage) values
 ('course-description-stale-retire', 'Platform upkeep', 19, 'Course descriptions: retire proposals that can no longer be approved',
  'Hourly at :13: finds course description proposals waiting in Layer 4 whose course is no longer active or already has a description another way and, only while Settings > Pipeline settings > Course description: retire proposals that can no longer be approved is on, supersedes them with the reason recorded (never an approval or a rejection). A proposal whose page changed or whose description is locked stays with a person. Counts only while the switch is off.',
  6, false, null)
on conflict (jobname) do nothing;
do $c$ begin
  if not exists (select 1 from cron.job where jobname = 'course-description-stale-retire') then
    perform cron.schedule('course-description-stale-retire', '13 * * * *', $j$select security.course_description_retire_stale_v1()$j$);
  end if;
end $c$;

-- 8. register -------------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.course_description_capacity_v1', 'Layer 4', 'Review capacity for waiting course descriptions (read only)', 'active', '{}', '20261108130000'),
 ('function', 'security.course_description_pack_v1', 'Layer 4', 'Review pack for waiting course descriptions: ordered, objective flags (read only)', 'active', '{}', '20261108130000'),
 ('function', 'security.course_description_retire_stale_v1', 'Layer 4', 'Supersede course description proposals that can no longer be approved (switch off by default)', 'active', '{}', '20261108130000'),
 ('job', 'course-description-stale-retire', 'Layer 4', 'CF-247 C-DESC: hourly retire of stale course description proposals (switch off by default)', 'active', '{}', '20261108130000')
on conflict do nothing;
update pipeline.component_register set note = coalesce(note || '. ', '') || '8 Nov 2026 (20261108130000): global back-pressure line (enrich.course_description_pending_global_max, off)', updated_at = now()
 where kind = 'function' and name = 'security.enrich_course_text_gaps_v1' and coalesce(note, '') not like '%20261108130000%';

-- 9. post-check -----------------------------------------------------------------------------------------------------------------------------------------
do $post$ begin
  if security.pipeline_num_v1('enrich.course_description_pending_global_max', -1) < 0 then raise exception 'post-check: the back-pressure setting is missing'; end if;
  if pg_get_functiondef('security.enrich_course_text_gaps_v1(text[])'::regprocedure) not like '%course_description_pending_global_max%' then raise exception 'post-check: the gap queue does not carry the back-pressure line'; end if;
  if pg_get_functiondef('public.admin_course_description_queue(text,jsonb)'::regprocedure) not like '%course_description_pack_v1%' then raise exception 'post-check: the Admin entry point does not carry the pack'; end if;
  if security.pipeline_num_v1('enrich.course_description_review_first', 0) < 1 then raise exception 'post-check: review_first must be untouched'; end if;
end $post$;
