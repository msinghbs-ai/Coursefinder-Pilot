CREATE OR REPLACE FUNCTION security.course_description_reconcile_v1(p_provider uuid DEFAULT NULL::uuid, p_recheck boolean DEFAULT false, p_cap integer DEFAULT NULL::integer)
 RETURNS TABLE(item_id uuid, provider_id uuid, country text, course_id uuid, course_title text, created_at timestamp with time zone, class text, why text, enrich_item bigint, rule text, checks jsonb, reask jsonb, rechecked boolean, evidence_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with p as (
    select r.id, r.entity_id, r.evidence_id, r.created_at,
           case when coalesce(r.proposed_value->>'item_id', '') ~ '^\d+$' then (r.proposed_value->>'item_id')::bigint end eid
      from pipeline.layer4_review_items r
     where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'course_description_first_read'),
  j as (
    select p.*, c.provider_id pid, c.lifecycle_status, nullif(btrim(c.description), '') now_desc, coalesce(nullif(c.display_title, ''), c.canonical_title) title,
           k.iso_alpha2::text country, g.evidence_id bound, e.value ev, e.id enrich_id,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('description', 'course_description', 'all')) locked,
           row_number() over (order by p.created_at, p.id) rn
      from p join catalogue.courses c on c.id = p.entity_id
      left join catalogue.providers pv on pv.id = c.provider_id
      left join ref.countries k on k.id = pv.country_id
      left join pipeline.coverage_course_pages g on g.course_id = c.id
      left join pipeline.field_enrich_items e on e.id = p.eid
     where p_provider is null or c.provider_id = p_provider),
  s as (
    select j.*, case when j.lifecycle_status is distinct from 'active' then 'course_inactive'
                     when j.now_desc is not null then 'already_filled'
                     when j.locked then 'locked'
                     when j.bound is distinct from j.evidence_id then 'page_changed'
                     when j.ev is null or jsonb_typeof(j.ev->'sentences') is distinct from 'array' or jsonb_array_length(j.ev->'sentences') = 0 then 'no_reading'
                end static_class,
           coalesce(p_recheck, false) and (p_cap is null or j.rn <= p_cap) do_check
      from j)
  select s.id, s.pid, s.country, s.entity_id, s.title, s.created_at,
         case when s.static_class is not null then s.static_class
              when z.chk is not null and not coalesce((z.chk->>'ok')::boolean, false) then 'fails_now' else 'ready' end,
         case s.static_class when 'course_inactive' then 'The course is no longer active.'
                             when 'already_filled' then 'The course already has a description, so this proposal cannot be approved as read.'
                             when 'locked' then 'The description is locked by hand.'
                             when 'page_changed' then 'The stored page this was read from is no longer the course''s bound page; it is read again with the new copy.'
                             when 'no_reading' then 'The AI reading behind this proposal is not stored, so its checks cannot be shown.'
                             else case when z.chk is not null and not coalesce((z.chk->>'ok')::boolean, false) then 'No longer passes the checks: ' || (z.chk->>'rule') || ': ' || coalesce(z.chk->>'reason', '')
                                       else 'A person can decide this as read.' end end,
         s.enrich_id, z.chk->>'rule', z.chk->'checks', s.ev->'reask', z.chk is not null, s.evidence_id
    from s left join lateral (select security.course_description_check_v1(s.entity_id, s.ev) chk where s.static_class is null and s.do_check) z on true
$function$
