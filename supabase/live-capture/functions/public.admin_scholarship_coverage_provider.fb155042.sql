CREATE OR REPLACE FUNCTION public.admin_scholarship_coverage_provider(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  pub as (select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = p_provider_id)),
  rec as (
    select s.id, jsonb_build_object('id', s.id, 'name', s.name, 'status', s.publication_status, 'audience', s.audience, 'source_url', s.source_url,
      'value_type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'value_text', s.award_value_text,
      'value_is_maximum', s.award_value_is_maximum, 'closes', s.application_close_date,
      'study_australia', security.reference_url_has_use(coalesce(s.source_url, ''), 'scholarship_placeholder'),
      'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'levels', (select coalesce(jsonb_agg(distinct sl.name), '[]'::jsonb) from scholarship.course_mappings cm join catalogue.courses c on c.id = cm.course_id
                   join ref.study_levels sl on sl.id = c.study_level_id where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'all_courses', exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id and sp.apply_result->'changes' ? 'course_links_all'),
      'publishable', coalesce((select x.publishable from pub x where x.scholarship_id = s.id), false),
      'reasons', coalesce((select to_jsonb(x.missing) from pub x where x.scholarship_id = s.id), '[]'::jsonb),
      'held', exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)) j
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select jsonb_build_object(
    'row', security.scholarship_coverage_row_v1(p_provider_id),
    'listing_pages', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'source', l.source, 'status', l.status, 'read_at', l.read_at, 'items', jsonb_array_length(l.items), 'error', l.error) order by (l.source = 'suggested'), l.id), '[]'::jsonb)
                        from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
    'listed', (select coalesce(jsonb_agg(jsonb_build_object('name', m.item_name, 'url', m.item_url, 'matched_by', m.matched_by, 'record', r.j) order by (m.scholarship_id is null) desc, m.item_name), '[]'::jsonb)
                 from m left join rec r on r.id = m.scholarship_id),
    'extra', (select coalesce(jsonb_agg(r.j order by (r.j->>'status') = 'published' desc, r.j->>'name'), '[]'::jsonb) from rec r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'can_manage', v_rank >= 6));
end $function$
