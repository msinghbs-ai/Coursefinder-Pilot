CREATE OR REPLACE FUNCTION security.layer4_resolution_for_v1(p_id uuid, p_entity_type text, p_entity_id uuid, p_field text, p_value jsonb, p_l2 jsonb, p_evidence uuid, p_created timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- {reason, covered_by_item, evidence} when the platform can settle the item without asking a person, otherwise null. In order:
--   entity_retired     its course (or the course's provider, or the provider) is missing or not active (the integration check's orphan rule);
--   duplicate_pending  an earlier waiting item asks the same question (same entity, kind, source and proposal);
--   decided_before     the same proposal was approved or rejected before this item was raised, and this item brings no new evidence
--                      (no stored page, or the same stored page or content; or, while layer4.same_page_new_copy_settles is 1, a newer copy
--                      of the same page address); a re-raise with new evidence stays for a person;
--   covered_by_active  the proposal is already the active value (the course's active official page; its active fee; its description).
-- An item whose supersession the Platform Admin reversed is never settled again.
declare v_key text := security.layer4_value_key_v1(p_field, p_value); v_scope text := security.layer4_scope_key_v1(p_field, p_l2, p_value);
        v_prov uuid; v_life text; v_plife text; v_hit record; v_hash text; v_url text; v_txt text;
        v_copy boolean := security.pipeline_num_v1('layer4.same_page_new_copy_settles', 0) >= 1;
begin
  -- the Platform Admin put this item back to waiting: it is asked, never settled again by the platform
  if p_id is not null and exists (select 1 from pipeline.layer4_supersessions s where s.item_id = p_id and s.reversed_at is not null) then return null; end if;
  if p_entity_type = 'course' then
    select c.provider_id, c.lifecycle_status into v_prov, v_life from catalogue.courses c where c.id = p_entity_id;
    select p.lifecycle_status into v_plife from catalogue.providers p where p.id = v_prov;
    if v_prov is null or v_life is distinct from 'active' or v_plife is distinct from 'active' then
      return jsonb_build_object('reason', 'entity_retired', 'evidence', jsonb_build_object('course_status', coalesce(v_life, 'missing'), 'provider_status', coalesce(v_plife, 'missing')));
    end if;
  elsif p_entity_type = 'provider' then
    select p.lifecycle_status into v_plife from catalogue.providers p where p.id = p_entity_id;
    if v_plife is distinct from 'active' then
      return jsonb_build_object('reason', 'entity_retired', 'evidence', jsonb_build_object('provider_status', coalesce(v_plife, 'missing')));
    end if;
  end if;
  select i.id, i.created_at into v_hit from pipeline.layer4_review_items i
   where i.entity_id = p_entity_id and i.field_code = p_field and i.status = 'pending' and i.entity_type = p_entity_type and i.id <> coalesce(p_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and (i.created_at, i.id) < (coalesce(p_created, now()), coalesce(p_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
     and security.layer4_scope_key_v1(i.field_code, i.layer2_state, i.proposed_value) = v_scope
     and security.layer4_value_key_v1(i.field_code, i.proposed_value) is not distinct from v_key
   order by i.created_at, i.id limit 1;
  if v_hit.id is not null then
    return jsonb_build_object('reason', 'duplicate_pending', 'covered_by_item', v_hit.id, 'evidence', jsonb_build_object('waiting_since', v_hit.created_at, 'value_key', v_key));
  end if;
  select e.content_hash, e.source_url into v_hash, v_url from pipeline.evidence_artifacts e where e.id = p_evidence;
  select i.id, i.status, i.decided_at, i.evidence_id into v_hit from pipeline.layer4_review_items i
   where i.entity_id = p_entity_id and i.field_code = p_field and i.entity_type = p_entity_type and i.status in ('approved', 'edited_approved', 'rejected')
     and i.decided_at is not null and i.decided_at < coalesce(p_created, now())
     and security.layer4_scope_key_v1(i.field_code, i.layer2_state, i.proposed_value) = v_scope
     and security.layer4_value_key_v1(i.field_code, i.proposed_value) is not distinct from v_key
     and (p_evidence is null or i.evidence_id = p_evidence
          or (v_hash is not null and v_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = i.evidence_id))
          or (v_copy and v_url is not null and v_url = (select e.source_url from pipeline.evidence_artifacts e where e.id = i.evidence_id)))
   order by i.decided_at desc limit 1;
  if v_hit.id is not null then
    return jsonb_build_object('reason', 'decided_before', 'covered_by_item', v_hit.id,
      'evidence', jsonb_build_object('decision', v_hit.status, 'decided_at', v_hit.decided_at, 'value_key', v_key,
                                     'same_evidence', case when p_evidence is null then 'no stored page on the new item' when v_hit.evidence_id = p_evidence then 'same stored page'
                                                           when v_hash = (select e.content_hash from pipeline.evidence_artifacts e where e.id = v_hit.evidence_id) then 'same page content'
                                                           else 'same page address, newer copy' end));
  end if;
  -- CF-247 Course Link (mandate 4 Nov 2026 16:32 §3): a question about the page the course shows (refused for this course by the binding check, an
  -- old-year address, an E16 two-page case) is not settled as "already the active page"; a person answers it
  if p_field = 'official_course_url' and v_key is not null and coalesce(p_l2->>'rule', '') not in ('address_year', 'e16_unclear')
     and coalesce(p_l2->>'source', '') not in ('housekeeping H13', 'e16 unclear')
     and not exists (select 1 from pipeline.page_rejections r where r.course_id = p_entity_id and security.layer4_url_key_v1(r.url) = v_key) then
    select l.id, l.url, l.is_primary into v_hit from catalogue.course_links l
     where l.course_id = p_entity_id and l.link_type = 'official_course' and l.status = 'active' and security.layer4_url_key_v1(l.url) = v_key
     order by l.is_primary desc limit 1;
    if v_hit.id is not null then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('course_link_id', v_hit.id, 'url', v_hit.url, 'primary', v_hit.is_primary));
    end if;
  elsif p_field in ('provider_current_tuition_validation', 'provider_current_tuition') and jsonb_typeof(p_value) = 'object' then
    select f.id, f.amount into v_hit from catalogue.course_fees f
     where f.course_id = p_entity_id and f.status = 'active' and f.fee_type = 'provider_current_tuition'
       and concat_ws('|', coalesce(f.amount::numeric(14, 2)::text, ''), coalesce(upper(f.currency_code), ''), coalesce(lower(f.basis), ''), coalesce(f.fee_year::text, ''),
                     lower(coalesce(f.audience, 'international'))) = v_key
     limit 1;
    if v_hit.id is not null then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('course_fee_id', v_hit.id, 'value_key', v_key));
    end if;
  elsif p_field = 'course_description_first_read' then
    select nullif(btrim(c.description), '') into v_txt from catalogue.courses c where c.id = p_entity_id;
    if v_txt is not null and v_txt = nullif(btrim(p_value->>'description'), '') then
      return jsonb_build_object('reason', 'covered_by_active', 'evidence', jsonb_build_object('description_chars', length(v_txt)));
    end if;
  end if;
  return null;
end $function$

