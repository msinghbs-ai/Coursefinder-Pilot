-- HELD (not a migration): forward recovery for 20261110060100 (the machine admission of first course descriptions), its four in-place edits of existing measures: security.course_description_summary_v1,
-- security.course_description_capacity_v1, security.course_description_sample_report_v1 and security.layer4_pace_v1 (a machine decision is not counted as a person's).
-- Run only if the Platform Admin decides to count machine decisions as the work of a person in these measures again. Each section restores one function byte for byte (the live body, read 10 Nov 2026) and is guarded
-- on its own by the md5 of what is live now (the edited text or the original); a function that is neither is left alone and the section stops with a message. Run the sections you want, one at a time if you prefer.
-- Bodies (pg_proc.prosrc md5), original -> edited: summary_v1 8e284898fdc7bda9dcbcc9d85acabace -> d5c88f55bcaadee970f7f3b2cc2ac25e; capacity_v1 ef83be9476da04995081ac04ab517bf0 -> 3ccb9929e42f7360056d7438570da110;
-- sample_report_v1 5854cf436c26cb814033f58a47e4d33e -> 55b26a23b44a8ce8c5db8502ceabeb62; layer4_pace_v1 344a3abad89b63baf9316a5d85f5f8ff -> 5a90aa3d1d421902ebe48692bba2322c.

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.course_description_summary_v1(uuid,boolean)'));
begin
  if v is null then raise exception 'security.course_description_summary_v1(uuid,boolean) is missing'; end if;
  if v not in ('d5c88f55bcaadee970f7f3b2cc2ac25e', '8e284898fdc7bda9dcbcc9d85acabace') then raise exception 'live security.course_description_summary_v1(uuid,boolean) differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.course_description_summary_v1(p_provider uuid DEFAULT NULL::uuid, p_recheck boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with r as (select * from security.course_description_reconcile_v1(p_provider, p_recheck, security.pipeline_num_v1('enrich.course_description_report_max', 500)::int)),
  cls as (select r.class, count(*) n from r group by 1),
  cty as (select coalesce(r.country, '?') country, count(*) n, count(*) filter (where r.class = 'ready') ready from r group by 1),
  l4 as (
    select i.id, i.status, c.id course_id, i.proposed_value->>'description' d, nullif(btrim(c.description), '') cur
      from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
     where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and (p_provider is null or c.provider_id = p_provider)),
  fe as (select f.* from pipeline.field_enrich_items f where f.field = 'description' and (p_provider is null or f.provider_id = p_provider))
  select jsonb_build_object(
    'provider_id', p_provider,
    'pending', (select count(*) from r),
    'by_class', coalesce((select jsonb_object_agg(cls.class, cls.n) from cls), '{}'::jsonb),
    'by_country', coalesce((select jsonb_object_agg(cty.country, jsonb_build_object('pending', cty.n, 'ready', cty.ready)) from cty), '{}'::jsonb),
    'rechecked', (select count(*) from r where r.rechecked),
    'oldest', (select min(r.created_at) from r),
    -- the four measures, never mixed: an AI reading waiting in Layer 4 is neither admitted nor published
    'proposed_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
    'waiting_behind_provider_cap', (select count(*) from fe where fe.state = 'skipped' and fe.reason like 'held\_first\_admission:%'),
    'admitted_by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved') and l4.cur is not distinct from nullif(btrim(l4.d), '')),
    'admitted_without_a_person', (select count(*) from fe where fe.state = 'filled' and coalesce(fe.value->>'admitted', '') <> ''),
    'published_to_the_website', (select count(distinct l4.course_id) from l4 join search.course_documents sd on sd.course_id = l4.course_id
                                   where l4.status in ('approved', 'edited_approved') and l4.cur is not distinct from nullif(btrim(l4.d), '') and nullif(btrim(sd.description), '') = l4.cur
                                     and sd.publication_status = 'published'
                                     and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = l4.course_id)),
    'decided', (select jsonb_object_agg(z.status, z.n) from (select l4.status, count(*) n from l4 group by 1) z),
    'limits', jsonb_build_object('min_sentences', security.pipeline_num_v1('enrich.course_description_min_sentences', 1), 'max_sentences', security.pipeline_num_v1('enrich.course_description_max_sentences', 4),
                                 'min_chars', security.pipeline_num_v1('enrich.course_description_min_chars', 80), 'max_chars', security.pipeline_num_v1('enrich.course_description_max_chars', 700)),
    'reask_max', security.pipeline_num_v1('enrich.course_description_reask_max', 0),
    'review_first', security.pipeline_num_v1('enrich.course_description_review_first', 100000),
    'note', 'Measurement only. A person admits every description in Layer 4; nothing here admits, decides or changes a setting.')
$function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_summary_v1(uuid,boolean)'))) <> '8e284898fdc7bda9dcbcc9d85acabace' then raise exception 'post-check: the restored security.course_description_summary_v1(uuid,boolean) does not match'; end if;
end $p$;

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.course_description_capacity_v1()'));
begin
  if v is null then raise exception 'security.course_description_capacity_v1() is missing'; end if;
  if v not in ('3ccb9929e42f7360056d7438570da110', 'ef83be9476da04995081ac04ab517bf0') then raise exception 'live security.course_description_capacity_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

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

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_capacity_v1()'))) <> 'ef83be9476da04995081ac04ab517bf0' then raise exception 'post-check: the restored security.course_description_capacity_v1() does not match'; end if;
end $p$;

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.course_description_sample_report_v1()'));
begin
  if v is null then raise exception 'security.course_description_sample_report_v1() is missing'; end if;
  if v not in ('55b26a23b44a8ce8c5db8502ceabeb62', '5854cf436c26cb814033f58a47e4d33e') then raise exception 'live security.course_description_sample_report_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.course_description_sample_report_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ids as (select * from security.course_description_sample_ids_v1()),
  pool as (select p.country, count(*) n from security.course_description_sample_pool_v1() p group by 1),
  strata as (select upper(x) code, o from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_sample_countries'), '[]'::jsonb)) with ordinality t(x, o)),
  claim as (select w from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w),
  dcn as (select distinct on (d.review_item_id) d.review_item_id, d.action, d.reason from pipeline.layer4_decisions d order by d.review_item_id, d.created_at desc),
  rws as (
    select ids.item_id, ids.country, ids.pick, i.status, dcn.action, dcn.reason,
           case when i.status in ('rejected', 'more_evidence', 'returned_layer2', 'returned_layer3')
                then coalesce(substring(dcn.reason from '^\s*\[(identity|support|marketing|fragment|other)\]'), 'unclassified') end reason_class,
           coalesce(pv.display_name, pv.canonical_name) provider, coalesce(nullif(c.display_title, ''), c.canonical_title) course, g.identity_basis, g.url page_url,
           i.proposed_value->>'description' description,
           (select min(security.pdesc_support_v1(s->>'text', s->>'quote')) from jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s) min_support,
           (select coalesce(jsonb_agg(distinct claim.w), '[]'::jsonb) from claim, jsonb_array_elements(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) s where security.pdesc_has_term_v1(s->>'text', claim.w)) claims,
           case when e.value is null then null else security.course_description_check_v1(c.id, e.value) end rules_now
      from ids join pipeline.layer4_review_items i on i.id = ids.item_id
      join catalogue.courses c on c.id = i.entity_id left join catalogue.providers pv on pv.id = c.provider_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.field_enrich_items e on e.id = case when coalesce(i.proposed_value->>'item_id', '') ~ '^\d+$' then (i.proposed_value->>'item_id')::bigint end
      left join dcn on dcn.review_item_id = i.id)
  select jsonb_build_object(
    'strata', coalesce((select jsonb_agg(jsonb_build_object('country', strata.code, 'wanted', security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0),
                          'eligible', coalesce(pool.n, 0), 'selected', (select count(*) from rws where rws.country = strata.code),
                          'shortfall', greatest(0, security.pipeline_num_v1('enrich.course_description_sample_' || lower(strata.code), 0) - (select count(*) from rws where rws.country = strata.code))) order by strata.o)
                          from strata left join pool on pool.country = strata.code), '[]'::jsonb),
    'selected', (select count(*) from rws),
    'pending', (select count(*) from rws where rws.status = 'pending'),
    'approved', (select count(*) from rws where rws.status in ('approved', 'edited_approved')),
    'rejected', (select count(*) from rws where rws.reason_class is not null),
    'approval_share_of_decided', (select round((count(*) filter (where rws.status in ('approved', 'edited_approved')))::numeric / nullif(count(*) filter (where rws.status <> 'pending'), 0), 3) from rws),
    'rejected_by_class', coalesce((select jsonb_object_agg(z.reason_class, z.n) from (select rws.reason_class, count(*) n from rws where rws.reason_class is not null group by 1) z), '{}'::jsonb),
    'reviewer_disagreement', jsonb_build_object(
        'passed_every_check_but_rejected', (select count(*) from rws where rws.reason_class is not null),
        'approved_but_rules_now_fail', (select count(*) from rws where rws.status in ('approved', 'edited_approved') and rws.rules_now is not null and not coalesce((rws.rules_now->>'ok')::boolean, false))),
    'claim_support', jsonb_build_object('with_claim_words_in_quote', (select count(*) from rws where jsonb_array_length(rws.claims) > 0), 'lowest_sentence_support', (select min(rws.min_support) from rws)),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('ref', rws.item_id, 'country', rws.country, 'provider', rws.provider, 'course', rws.course, 'status', rws.status,
                        'reason_class', rws.reason_class, 'reason', rws.reason, 'min_support', rws.min_support, 'claims', rws.claims, 'identity_basis', rws.identity_basis,
                        'page_url', rws.page_url, 'description', rws.description, 'rules_now', rws.rules_now) order by rws.country, rws.pick) from rws), '[]'::jsonb),
    'note', 'A measurement of what the checks let through, decided by a person in Layer 4. It is not an authority to bypass Layer 4 and does not change enrich.course_description_review_first.')
$function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.course_description_sample_report_v1()'))) <> '5854cf436c26cb814033f58a47e4d33e' then raise exception 'post-check: the restored security.course_description_sample_report_v1() does not match'; end if;
end $p$;

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.layer4_pace_v1()'));
begin
  if v is null then raise exception 'security.layer4_pace_v1() is missing'; end if;
  if v not in ('5a90aa3d1d421902ebe48692bba2322c', '344a3abad89b63baf9316a5d85f5f8ff') then raise exception 'live security.layer4_pace_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.layer4_pace_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Per kind: the median minutes between consecutive decisions of one reviewer, counting only gaps above layer4.pace_min_gap_seconds (closer ones
-- are bulk actions) and up to layer4.pace_gap_minutes (longer gaps are breaks); kinds with fewer than layer4.pace_min_decisions measured decisions use layer4.pace_default_minutes. {kind: {minutes, measured, basis}}.
  with d as (select r.field_code, extract(epoch from x.created_at - lag(x.created_at) over (partition by x.actor_id order by x.created_at)) / 60.0 gap
               from pipeline.layer4_decisions x join pipeline.layer4_review_items r on r.id = x.review_item_id
              where x.created_at > now() - make_interval(days => security.pipeline_num_v1('layer4.pace_window_days', 30)::int) and x.actor_id is not null),
       k as (select d.field_code, count(*) n, percentile_cont(0.5) within group (order by d.gap) p50 from d
              where d.gap > security.pipeline_num_v1('layer4.pace_min_gap_seconds', 20) / 60.0 and d.gap <= security.pipeline_num_v1('layer4.pace_gap_minutes', 15) group by d.field_code)
  select coalesce(jsonb_object_agg(k.field_code, jsonb_build_object(
           'minutes', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then round(k.p50::numeric, 2) else security.pipeline_num_v1('layer4.pace_default_minutes', 3) end,
           'measured', k.n, 'basis', case when k.n >= security.pipeline_num_v1('layer4.pace_min_decisions', 5) then 'measured' else 'default' end)), '{}'::jsonb)
    from k
$function$;

do $p$ begin
  if md5((select p.prosrc from pg_proc p where p.oid = to_regprocedure('security.layer4_pace_v1()'))) <> '344a3abad89b63baf9316a5d85f5f8ff' then raise exception 'post-check: the restored security.layer4_pace_v1() does not match'; end if;
end $p$;
