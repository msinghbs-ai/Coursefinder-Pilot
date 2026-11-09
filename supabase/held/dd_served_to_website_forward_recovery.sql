-- HELD (not a migration): forward recovery for 20261110130000 (Data Delivery counts what the Website serves), its one in-place edit: security.data_delivery_cdesc_stages_v1.
-- Run only if the Platform Admin decides to take the edit back. It restores the function byte for byte (the live body, read 10 Nov 2026), guarded by the md5 of what is live now (the edited text,
-- d2a913a4d294f71fadf949bff6786f94, or the original eeb3d57c652c66d3f11f38c4de44068b); a function that is neither stops with a message. The original body counted the course flag
-- (search.course_documents.publication_status = 'published'), which is not what the Website serves; it is kept here for recovery only.

do $g$
declare v text := (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('security.data_delivery_cdesc_stages_v1()'));
begin
  if v is null then raise exception 'security.data_delivery_cdesc_stages_v1() is missing'; end if;
  if v not in ('d2a913a4d294f71fadf949bff6786f94', 'eeb3d57c652c66d3f11f38c4de44068b') then raise exception 'live security.data_delivery_cdesc_stages_v1() differs from both texts this recovery knows (body md5 %)', v; end if;
end $g$;

CREATE OR REPLACE FUNCTION security.data_delivery_cdesc_stages_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_top int := security.pipeline_num_v1('data_delivery.reasons_shown', 3)::int; -- derived: the existing Data Delivery setting, how many exact reasons a stream lists
begin
  return (
  with l4 as (select i.id, i.status, i.entity_id from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read'),
       led as (select a.course_id, a.review_item_id, a.outcome, a.reason_code, a.reason, a.created_at, a.withdrawn_at, a.consumer_check from pipeline.course_description_machine_admissions a),
       live_m as (select l.course_id, coalesce(l.consumer_check, 'not_checked') chk from led l where l.outcome = 'admitted' and l.withdrawn_at is null),
       declined as (select l.reason_code, l.reason, l.created_at from led l join l4 on l4.id = l.review_item_id where l.outcome = 'declined' and l4.status = 'pending'),
       top as (select d.reason_code code, count(*) n, (array_agg(d.reason order by d.created_at desc))[1] example from declined d group by 1 order by 2 desc, 1 limit v_top),
       described as (select c.id from catalogue.courses c where nullif(btrim(c.description), '') is not null),
       shown as (select d.course_id from search.course_documents d where d.publication_status = 'published' and not exists (select 1 from security.layer4_search_blocked_courses b where b.course_id = d.course_id)),
       held as (select count(*) filter (where f.reason like 'held\_first\_admission:%') behind_cap, count(*) filter (where f.reason like 'held: %') by_check
                  from pipeline.field_enrich_items f where f.field = 'description' and f.state = 'skipped'),
       zl as (select z.item ? 'description' has_key from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null order by z.seq desc limit 1)
  select jsonb_build_object(
    'known', true, 'counted_at', now(), 'unit', 'courses',
    'source', jsonb_build_object('proposals_from_a_stored_page', (select count(*) from pipeline.layer4_review_items i where i.entity_type = 'course' and i.field_code = 'course_description_first_read' and i.evidence_id is not null)),
    'proposal', jsonb_build_object('waiting_in_layer4', (select count(*) from l4 where l4.status = 'pending'),
                                   'held_behind_provider_cap', (select behind_cap from held), 'held_by_a_check', (select by_check from held)),
    'validation', jsonb_build_object('not_yet_checked_by_machine', (select count(*) from l4 where l4.status = 'pending' and not exists (select 1 from led l where l.review_item_id = l4.id)),
                                     'declined_by_machine', (select count(*) from declined),
                                     'top_decline_reasons', coalesce((select jsonb_agg(jsonb_build_object('code', t.code, 'n', t.n, 'example', t.example) order by t.n desc, t.code) from top t), '[]'::jsonb)),
    'admitted', jsonb_build_object('by_machine', (select count(*) from live_m),
                                   'by_person', (select count(*) from l4 where l4.status in ('approved', 'edited_approved')
                                                    and not exists (select 1 from pipeline.layer4_decisions md where md.review_item_id = l4.id and md.layer2_state->>'actor_kind' = 'machine')),
                                   'withdrawn', (select count(*) from led where outcome = 'admitted' and withdrawn_at is not null),
                                   'described_courses', (select count(*) from described),
                                   'described_other_route', (select count(*) from described d where d.id not in (select course_id from live_m) and d.id not in (select l4.entity_id from l4 where l4.status in ('approved', 'edited_approved')))),
    'consumers', jsonb_build_object('website_published', (select count(*) from described d where d.id in (select course_id from shown)),
                                    'unpublished_course', (select count(*) from described d where d.id not in (select course_id from shown)),
                                    'machine_readback', jsonb_build_object('matched', (select count(*) from live_m where chk = 'matched'), 'lag', (select count(*) from live_m where chk = 'lag'),
                                                                           'not_in_feed', (select count(*) from live_m where chk = 'not_in_feed'), 'error', (select count(*) from live_m where chk = 'error'),
                                                                           'not_checked', (select count(*) from live_m where chk not in ('matched', 'lag', 'not_in_feed', 'error'))),
                                    'zoho', coalesce((select case when zl.has_key then jsonb_build_object('known', false, 'reason', 'The Zoho course feed now carries a description field, but how many reach Zoho is not counted yet.')
                                                         else jsonb_build_object('known', false, 'reason', 'The latest course item in the Zoho course feed has no description field, so a course description does not reach Zoho. Nothing is counted for it.') end from zl),
                                                    jsonb_build_object('known', false, 'reason', 'The Zoho course feed holds no course item, so nothing is counted for it.'))))
  );
exception when others then
  -- a count that cannot be made is shown as such, never as 0, and does not stop the rest of Data Delivery
  return jsonb_build_object('known', false, 'reason', 'The stage counts could not be read: ' || sqlerrm);
end $function$;
