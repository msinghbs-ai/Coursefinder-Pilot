CREATE OR REPLACE FUNCTION security.layer4_course_link_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'search'
AS $function$
declare v_item pipeline.layer4_review_items%rowtype; v_url text; v_host text; v_link uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  if v_item.entity_type<>'course' then raise exception 'course links apply to courses only'; end if;
  -- CF-247 17 Oct 2026: the proposed page may be stored as url or course_url
  v_url := btrim(coalesce(case jsonb_typeof(p_value) when 'string' then p_value#>>'{}' when 'object' then coalesce(p_value->>'url', p_value->>'course_url') end,
                          case jsonb_typeof(v_item.proposed_value) when 'string' then v_item.proposed_value#>>'{}' when 'object' then coalesce(v_item.proposed_value->>'url', v_item.proposed_value->>'course_url') end,''));
  if v_url='' then raise exception 'enter the official course page link, then approve'; end if;
  if v_url !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^\s]*)?$' then raise exception 'the link must be a full https:// web address'; end if;
  v_host := lower(substring(v_url from '^https://([^/]+)'));
  if security.reference_url_has_use(v_url, 'not_course_page') then
    raise exception 'use the provider''s own course page, not a search, social or course-listing site (%)', v_host;
  end if;
  insert into catalogue.course_links(course_id,link_type,url,audience,label,is_primary,status,source_id,evidence_id,confidence,last_verified_at,updated_at)
  values (v_item.entity_id,'official_course',v_url,'international','Official provider course page (confirmed by reviewer)',false,'active',(select id from pipeline.sources where source_type='layer4_human_review' limit 1),v_item.evidence_id,1,now(),now())
  on conflict(course_id,link_type,url) do update set label=excluded.label,status='active',source_id=excluded.source_id,confidence=1,last_verified_at=now(),updated_at=now()
  returning id into v_link;
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object('course_link_id',v_link,'url',v_url,'search_refreshed',true);
end $function$
